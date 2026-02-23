# -*- encoding: binary -*-
# Copyright (C) 2015-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

require_relative 'wbuf_lite'

# loaded by yahns/proxy_pass, this relies on Yahns::HttpResponse for
# constants.
module Yahns::HttpResponse # :nodoc:

  # switch and yield
  def proxy_unbuffer(wbuf, nxt = :ignore)
    @state = wbuf
    wbuf.req_res = nil if nxt.nil? && wbuf.respond_to?(:req_res=)
    proxy_wait_next(wbuf.busy == :wait_readable ? Yahns::Queue::QEV_RD :
                    Yahns::Queue::QEV_WR)
    nxt
  end

  def wbuf_alloc(req_res)
    if req_res.proxy_pass.proxy_buffering
      Yahns::Wbuf.new(nil, req_res.alive)
    else
      Yahns::WbufLite.new(req_res)
    end
  end

  # write everything in buf to our client socket (or wbuf, if it exists)
  # it may return a newly-created wbuf or nil
  def proxy_write(wbuf, buf, req_res)
    unless wbuf
      # no write buffer, try to write directly to the client socket
      case rv = String === buf ? kgio_trywrite(buf) : kgio_trywritev(buf)
      when nil then return # done writing buf, likely
      when String, Array # partial write, hope the skb grows
        buf = rv
      when :wait_writable, :wait_readable
        wbuf = req_res.resbuf ||= wbuf_alloc(req_res)
        break
      end while true
    end

    wbuf.wbuf_write(self, buf)
    wbuf.busy ? wbuf : nil
  end

  def proxy_err_response(code, req_res, exc)
    logger = self.class.logger # Yahns::HttpContext#logger
    case exc
    when nil
      logger.error('premature upstream EOF')
    when Kcar::ParserError
      logger.error("upstream response error: #{exc.message}")
    when String
      logger.error(exc)
    else
      Yahns::Log.exception(logger, 'upstream error', exc)
    end
    # try to write something, but don't care if we fail
    Integer === code and
      kgio_trywrite("HTTP/1.1 #{code} #{
                     Rack::Utils::HTTP_STATUS_CODES[code]}\r\n\r\n") rescue nil

    shutdown rescue nil
    @input = @input.close if @input

    # this is safe ONLY because we are in an :ignore state after
    # Fdmap#forget when we got hijacked:
    close

    nil # signal close of req_res from yahns_step in yahns/proxy_pass.rb
  ensure
    wbuf = req_res.resbuf
    wbuf.wbuf_abort if wbuf.respond_to?(:wbuf_abort)
  end

  def wait_on_upstream(req_res)
    req_res.resbuf ||= wbuf_alloc(req_res)
    :wait_readable # self remains in :ignore, wait on upstream
  end

  def proxy_res_headers(res, req_res)
    status, headers = res
    code = status.to_i
    msg = Rack::Utils::HTTP_STATUS_CODES[code]
    env = @hs.env
    have_body = !Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(code) &&
                env['REQUEST_METHOD'] != 'HEAD'.freeze
    flags = MSG_DONTWAIT
    alive = @hs.next? && self.class.persistent_connections
    term = false
    response_headers = req_res.proxy_pass.response_headers

    res = "HTTP/1.1 #{msg ? %Q(#{code} #{msg}) : status}\r\n".dup
    headers.each do |key,value| # n.b.: headers is an Array of 2-element Arrays
      case key
      when /\A(?:Connection|Keep-Alive)\z/i
        next # do not let some upstream headers leak through
      when %r{\AContent-Length\z}i
        term = true
        flags |= MSG_MORE if have_body && value.to_i > 0
      when %r{\ATransfer-Encoding\z}i
        term = true if value =~ /\bchunked\b/i
      end

      # response header mapping
      case val = response_headers[key]
      when :ignore
        next
      when String
        value = val
      end

      res << "#{key}: #{value}\r\n"
    end

    # For now, do not add a Date: header, assume upstream already did it
    # but do not care if they did not

    # chunk the response ourselves if the client supports it,
    # but the backend does not terminate properly
    if alive && ! term && have_body
      if env['HTTP_VERSION'] == 'HTTP/1.1'.freeze
        res << "Transfer-Encoding: chunked\r\n".freeze
      else # we can't persist HTTP/1.0 and HTTP/0.9 w/o Content-Length
        alive = false
      end
    end
    res << (alive ? "Connection: keep-alive\r\n\r\n".freeze
                  : "Connection: close\r\n\r\n".freeze)

    # send the headers
    case rv = kgio_syssend(res, flags)
    when nil # all done, likely
      res.clear
      break
    when String # partial write, highly unlikely
      flags = MSG_DONTWAIT
      res = rv # hope the skb grows
    when :wait_writable, :wait_readable # highly unlikely in real apps
      proxy_write(nil, res, req_res)
      break # keep buffering body...
    end while true
    req_res.alive = alive
    have_body
  end

  def proxy_read_body(tip, kcar, req_res)
    chunk = ''.dup if kcar.chunked?
    len = kcar.body_bytes_left
    rbuf = Thread.current[:yahns_rbuf]
    alive = req_res.alive
    wbuf = req_res.resbuf

    case tmp = tip.shift || req_res.kgio_tryread(0x2000, rbuf)
    when String
      if len
        kcar.body_bytes_left -= tmp.size # progress for body_eof? => true
      elsif chunk
        kcar.filter_body(chunk, rbuf = tmp) # progress for body_eof? => true
        next if chunk.empty? # call req_res.kgio_tryread for more
        tmp = chunk_out(chunk)
      elsif alive # HTTP/1.0 upstream, HTTP/1.1 client
        tmp = chunk_out(tmp)
      # else # HTTP/1.0 upstream, HTTP/1.0 client, do nothing
      end
      wbuf = proxy_write(wbuf, tmp, req_res)
      chunk.clear if chunk
      if Yahns::WbufLite === wbuf
        req_res.proxy_trailers = [ rbuf.dup, tip ] if chunk && kcar.body_eof?
        return proxy_unbuffer(wbuf)
      end
    when nil # EOF
      # HTTP/1.1 upstream, unexpected premature EOF:
      msg = "upstream EOF (#{len} bytes left)" if len
      msg = 'upstream EOF (chunk)' if chunk
      return proxy_err_response(nil, req_res, msg) if msg

      # HTTP/1.0 upstream:
      wbuf = proxy_write(wbuf, "0\r\n\r\n".freeze, req_res) if alive
      req_res.shutdown
      return proxy_unbuffer(wbuf, nil) if Yahns::WbufLite === wbuf
      return proxy_busy_mod(wbuf, req_res)
    when :wait_readable
      return wait_on_upstream(req_res)
    end until kcar.body_eof?

    if chunk
      # tip is an empty array and becomes trailer storage
      req_res.proxy_trailers = [ rbuf.dup, tip ]
      return proxy_read_trailers(kcar, req_res)
    end
    proxy_busy_mod(wbuf, req_res)
  end

  def proxy_read_trailers(kcar, req_res)
    chunk, tlr = req_res.proxy_trailers
    rbuf = Thread.current[:yahns_rbuf]
    wbuf = req_res.resbuf

    until kcar.trailers(tlr, chunk)
      case rv = req_res.kgio_tryread(0x2000, rbuf)
      when String
        chunk << rv
      when :wait_readable
        return wait_on_upstream(req_res)
      when nil # premature EOF
        return proxy_err_response(nil, req_res, 'upstream EOF (trailers)')
      end # no loop here
    end
    wbuf = proxy_write(wbuf, trailer_out(tlr), req_res)
    return proxy_unbuffer(wbuf) if Yahns::WbufLite === wbuf
    proxy_busy_mod(wbuf, req_res)
  end

  # start streaming the response once upstream is done sending headers to us.
  # returns :wait_readable if we need to read more from req_res
  # returns :ignore if we yield control to the client(self)
  # returns nil if completely done
  def proxy_response_start(res, tip, kcar, req_res)
    have_body = proxy_res_headers(res, req_res)
    tip = tip.empty? ? [] : [ tip ]

    if have_body
      req_res.proxy_trailers = nil # define to avoid uninitialized warnings
      return proxy_read_body(tip, kcar, req_res)
    end

    # unlikely
    wbuf = req_res.resbuf
    return proxy_unbuffer(wbuf) if Yahns::WbufLite === wbuf

    # all done reading response from upstream, req_res will be discarded
    # when we return nil:
    proxy_busy_mod(wbuf, req_res)
  end

  def proxy_response_finish(kcar, req_res)
    req_res.proxy_trailers ? proxy_read_trailers(kcar, req_res)
                           : proxy_read_body([], kcar, req_res)
  end

  def proxy_wait_next(qflags)
    Thread.current[:yahns_fdmap].remember(self)
    # We must allocate a new, empty request object here to avoid a TOCTTOU
    # in the following timeline
    #
    # original thread:                                 | another thread
    # HttpClient#yahns_step                            |
    # r = k.app.call(env = @hs.env)  # socket hijacked into epoll queue
    # <thread is scheduled away>                       | epoll_wait readiness
    #                                                  | ReqRes#yahns_step
    #                                                  | proxy dispatch ...
    #                                                  | proxy_busy_mod
    # ************************** DANGER BELOW ********************************
    #                                                  | HttpClient#yahns_step
    #                                                  | # clears env
    # sees empty env:                                  |
    # return :ignore if env.include?('rack.hijack_io') |
    #
    # In other words, we cannot touch the original env seen by the
    # original thread since it must see the 'rack.hijack_io' value
    # because both are operating in the same Yahns::HttpClient object.
    # This will happen regardless of GVL existence
    hs = Unicorn::HttpRequest.new
    hs.buf.replace(@hs.buf)
    @hs = hs

    # n.b. we may not touch anything in this object once we call queue_mod,
    # another thread is likely to take it!
    Thread.current[:yahns_queue].queue_mod(self, qflags)
  end

  def proxy_busy_mod(wbuf, req_res)
    if wbuf
      # we are completely done reading and buffering the upstream response,
      # but have not completely written the response to the client,
      # yield control to the client socket:
      @state = wbuf
      proxy_wait_next(wbuf.busy == :wait_readable ? Yahns::Queue::QEV_RD :
                      Yahns::Queue::QEV_WR)
      # no touching self after proxy_wait_next, we may be running
      # HttpClient#yahns_step in a different thread at this point
    else
      case http_response_done(req_res.alive)
      when :wait_readable then proxy_wait_next(Yahns::Queue::QEV_RD)
      when :wait_writable then proxy_wait_next(Yahns::Queue::QEV_WR)
      when :close then close
      end
    end
    nil # signal close for ReqRes#yahns_step
  end

  # n.b.: we can use String#size for optimized dispatch under YARV instead
  # of String#bytesize because all the IO read methods return a binary
  # string when given a maximum read length
  def chunk_out(buf)
    [ "#{buf.size.to_s(16)}\r\n", buf, "\r\n".freeze ]
  end

  def trailer_out(tlr)
    "0\r\n#{tlr.map! do |k,v| "#{k}: #{v}\r\n" end.join}\r\n"
  end
end
