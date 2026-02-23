# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
# Only used by Yahns::ProxyPass
require 'kcar' # gem install kcar
require 'kgio'

class Yahns::ReqRes < Kgio::Socket # :nodoc:
  attr_accessor :resbuf
  attr_accessor :proxy_trailers
  attr_accessor :alive
  attr_reader :proxy_pass

  def req_start(c, req, input, chunked, proxy_pass)
    @hdr = @resbuf = nil
    @yahns_client = c
    @rrstate = input ? [ req, input, chunked ] : req
    @proxy_pass = proxy_pass
    Thread.current[:yahns_queue].queue_add(self, Yahns::Queue::QEV_WR)
  end

  def yahns_step # yahns event loop entry point
    c = @yahns_client
    case req = @rrstate
    when Kcar::Parser # reading response...
      buf = Thread.current[:yahns_rbuf]

      case resbuf = @resbuf # where are we at the response?
      when nil # common case, catch the response header in a single read

        case rv = kgio_tryread(0x2000, buf)
        when String
          if res = req.headers(@hdr = [], rv)
            return c.proxy_response_start(res, rv, req, self)
          else # ugh, big headers or tricked response
            # we must reinitialize the thread-local rbuf if it may
            # live beyond the current thread
            buf = Thread.current[:yahns_rbuf] = ''.dup
            @resbuf = rv
          end
          # continue looping in middle "case @resbuf" loop
        when :wait_readable
          return rv # spurious wakeup
        when nil
          return c.proxy_err_response(502, self, 'upstream EOF (headers)')
        end # NOT looping here

      when String # continue reading trickled response headers from upstream

        case rv = kgio_tryread(0x2000, buf)
        when String then res = req.headers(@hdr, resbuf << rv) and break
        when :wait_readable then return rv
        when nil
          return c.proxy_err_response(502, self, 'upstream EOF (big headers)')
        end while true
        @resbuf = false

        return c.proxy_response_start(res, resbuf, req, self)

      when Yahns::WbufCommon # streaming/buffering the response body

        return c.proxy_response_finish(req, self)

      end while true # case @resbuf

    when Array # [ (str|vec), rack.input, chunked? ]
      send_req_body(req) # returns nil or :wait_writable
    when String # buffered request header
      send_req_buf(req)
    end
  rescue => e
    # avoid polluting logs with a giant backtrace when the problem isn't
    # fixable in code.
    case e
    when Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE
      e.set_backtrace([])
    end
    c.proxy_err_response(Yahns::WbufCommon === @resbuf ? nil : 502, self, e)
  end

  def send_req_body_chunk(buf)
    case rv = String === buf ? kgio_trywrite(buf) : kgio_trywritev(buf)
    when String, Array
      buf.replace(rv) # retry loop on partial write
    when :wait_writable, nil
      # :wait_writable = upstream is reading slowly and making us wait
      return rv
    else
      abort "BUG: #{rv.inspect} from kgio_trywrite*"
    end while true
  end

  # returns :wait_readable if complete, :wait_writable if not
  def send_req_body(req) # @rrstate == [ (str|vec), rack.input, chunked? ]
    buf, input, chunked = req

    # send the first buffered chunk or vector
    rv = send_req_body_chunk(buf) and return rv # :wait_writable

    # yay, sent the first chunk, now read the body!
    rbuf = buf
    if chunked
      if String === buf # initial body
        req[0] = buf = []
      else
        # try to reuse the biggest non-frozen buffer we just wrote;
        rbuf = buf.max_by(&:size)
        rbuf = ''.dup if rbuf.frozen? # unlikely...
      end
    end

    # Note: input (env['rack.input']) is fully-buffered by default so
    # we should not be waiting on a slow network resource when reading
    # input.  However, some weird configs may disable this on LANs
    # and we may wait indefinitely on input.read here...
    while input.read(0x2000, rbuf)
      if chunked
        buf[0] = "#{rbuf.size.to_s(16)}\r\n".freeze
        buf[1] = rbuf
        buf[2] = "\r\n".freeze
      end
      rv = send_req_body_chunk(buf) and return rv # :wait_writable
    end

    rbuf.clear # all done, clear the big buffer

    # we cannot use respond_to?(:close) here since Rack::Lint::InputWrapper
    # tries to prevent that (and hijack means all Rack specs go out the door)
    case input
    when Yahns::TeeInput, IO
      input.close
    end

    # note: we do not send any trailer, they are folded into the header
    # because this relies on full request buffering
    # prepare_wait_readable is called by send_req_buf
    chunked ? send_req_buf("0\r\n\r\n".freeze) : prepare_wait_readable
  rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN
    # no more reading off the client socket, just prepare to forward
    # the rejection response from the upstream (if any)
    @yahns_client.to_io.shutdown(Socket::SHUT_RD)
    prepare_wait_readable
  end

  def prepare_wait_readable
    @rrstate = Kcar::Parser.new
    :wait_readable # all done sending the request, wait for response
  end

  # n.b. buf must be a detached string not shared with
  # Thread.current[:yahns_rbuf] of any thread
  def send_req_buf(buf)
    case rv = kgio_trywrite(buf)
    when String
      buf = rv # retry inner loop
    when :wait_writable
      @rrstate = buf
      return :wait_writable
    when nil
      return prepare_wait_readable
    end while true
  end
end # class ReqRes
