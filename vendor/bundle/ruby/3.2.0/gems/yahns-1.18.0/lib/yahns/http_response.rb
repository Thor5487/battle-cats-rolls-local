# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'stream_file'
require_relative 'wbuf_str'
require_relative 'chunk_body'

# Writes a Rack response to your client using the HTTP/1.1 specification.
# You use it by simply doing:
#
#   opt = http_response_prep(env)
#   res = rack_app.call(env)
#   http_response_write(res, opt)
#
# Most header correctness (including Content-Length and Content-Type)
# is the job of Rack, with the exception of the "Date" header.
module Yahns::HttpResponse # :nodoc:
  include Unicorn::HttpResponse

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == "rbx"
    MTX = Mutex.new
    def httpdate
      MTX.synchronize { super }
    end
  end

  # avoid GC overhead for frequently used-strings/objects:
  CCC_RESPONSE_START = [ 'HTTP', '/1.1 ' ]

  # no point in using one without the other, these have been in Linux
  # for ages
  if Socket.const_defined?(:MSG_MORE) && Socket.const_defined?(:MSG_DONTWAIT)
    MSG_MORE = Socket::MSG_MORE
    MSG_DONTWAIT = Socket::MSG_DONTWAIT
  else
    MSG_MORE = 0
    MSG_DONTWAIT = 0

    def kgio_syssend(buf, flags)
      kgio_trywrite(buf)
    end
  end

  def response_start
    @hs.response_start_sent ? ''.freeze : 'HTTP/1.1 '.freeze
  end

  def response_wait_write(rv) # rv = [:wait_writable | :wait_readable ]
    k = self.class
    ok = __send__(rv, k.client_timeout) and return ok
    k.logger.info("fd=#{fileno} ip=#@kgio_addr timeout on :#{rv} after "\
                  "#{k.client_timeout}s")
    false
  end

  def err_response(code)
    "#{response_start}#{code} #{Rack::Utils::HTTP_STATUS_CODES[code]}\r\n\r\n"
  end

  def response_header_blocked(header, body, alive, offset, count)
    if body.respond_to?(:to_path) && count
      alive = Yahns::StreamFile.new(body, alive, offset, count)
      body = nil
    end
    wbuf = Yahns::Wbuf.new(body, alive)
    rv = wbuf.wbuf_write(self, header)
    if body && ! alive.respond_to?(:call) # skip body.each if hijacked
      body.each { |chunk| rv = wbuf.wbuf_write(self, chunk) }
    end
    wbuf_maybe(wbuf, rv)
  end

  def wbuf_maybe(wbuf, rv)
    case rv # wbuf_write return value
    when nil # all done
      case rv = wbuf.wbuf_close(self)
      when :ignore # hijacked
        @state = rv
      when Yahns::StreamFile
        @state = rv
        :wait_writable
      when true, false
        http_response_done(rv)
      end
    else
      @state = wbuf
      rv
    end
  end

  def http_response_done(alive)
    @input = @input.close if @input
    if alive
      # @hs.buf will have data if the client pipelined
      if @hs.buf.empty?
        @state = :headers
        :wait_readable
      else
        @state = :pipelined
        # we shouldn't start processing the application again until we know
        # the socket is writable for the response
        :wait_writable
      end
    else
      # shutdown is needed in case the app forked, we rescue here since
      # StreamInput may issue shutdown as well
      shutdown rescue nil
      :close
    end
  end

  def kv_str(buf, key, value)
    if value.include?("\n".freeze)
      # avoiding blank, key-only cookies with /\n+/
      value.split(/\n+/).each { |v| buf << "#{key}: #{v}\r\n" }
    else
      buf << "#{key}: #{value}\r\n"
    end
  end

  # writes the rack_response to socket as an HTTP response
  # returns :wait_readable, :wait_writable, :forget, or nil
  def http_response_write(res, opt)
    status, headers, body = res
    offset = 0
    count = hijack = clen = nil
    alive = @hs.next? && self.class.persistent_connections
    flags = MSG_DONTWAIT
    term = false
    hdr_only, chunk_ok = opt

    code = status.to_i
    hdr_only ||= Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(code)
    msg = Rack::Utils::HTTP_STATUS_CODES[code]
    buf = "#{response_start}#{msg ? %Q(#{code} #{msg}) : status}\r\n" \
          "Date: #{httpdate}\r\n".dup
    headers.each do |key, value|
      case key
      when %r{\ADate\z}i
        next
      when %r{\AContent-Range\z}i
        if %r{\Abytes (\d+)-(\d+)/\d+\z} =~ value
          offset = $1.to_i
          count = $2.to_i - offset + 1
        end
        kv_str(buf, key, value)
      when %r{\AConnection\z}i
        # allow Rack apps to tell us they want to drop the client
        alive = false if value =~ /\bclose\b/i
      when %r{\AContent-Length\z}i
        term = true
        clen = value.to_i
        flags |= MSG_MORE if clen > 0 && !hdr_only
        kv_str(buf, key, value)
      when %r{\ATransfer-Encoding\z}i
        term = true if value =~ /\bchunked\b/i
        kv_str(buf, key, value)
      when "rack.hijack"
        hijack = value
      else
        kv_str(buf, key, value)
      end
    end
    count ||= clen

    if !term && chunk_ok && !hdr_only
      term = true
      body = Yahns::ChunkBody.new(body, opt)
      buf << "Transfer-Encoding: chunked\r\n".freeze
    end
    alive &&= (term || hdr_only)
    buf << (alive ? "Connection: keep-alive\r\n\r\n".freeze
                  : "Connection: close\r\n\r\n".freeze)
    case rv = kgio_syssend(buf, flags)
    when nil # all done, likely
      buf.clear
      buf = nil # recycle any memory we used ASAP
      break
    when String
      flags = MSG_DONTWAIT
      buf = rv # unlikely, hope the skb grows
    when :wait_writable, :wait_readable # unlikely
      if self.class.output_buffering
        alive = hijack ? hijack : alive
        rv = response_header_blocked(buf, body, alive, offset, count)
        body = nil # ensure we do not close body in ensure
        return rv
      else
        response_wait_write(rv) or return :close
      end
    end while @hs.headers?

    return response_hijacked(hijack) if hijack
    return http_response_done(alive) if hdr_only

    if body.respond_to?(:to_path) && count
      @state = body = Yahns::StreamFile.new(body, alive, offset, count)
      return step_write
    end

    headers = wbuf = rv = nil
    body.each do |x|
      if wbuf
        rv = wbuf.wbuf_write(self, x)
      else
        case rv = String === x ? kgio_trywrite(x) : kgio_trywritev(x)
        when nil # all done, likely and good!
          break
        when String, Array
          x = rv # hope the skb grows when we loop into the trywrite
        when :wait_writable, :wait_readable
          if self.class.output_buffering
            wbuf = Yahns::Wbuf.new(body, alive)
            rv = wbuf.wbuf_write(self, x)
            break
          else
            response_wait_write(rv) or return :close
          end
        end while true
      end
    end

    # if we buffered the write body, we must return :wait_writable
    # (or :wait_readable for SSL) and hit Yahns::HttpClient#step_write
    if wbuf
      body = nil # ensure we do not close the body in ensure
      wbuf_maybe(wbuf, rv)
    else
      http_response_done(alive)
    end
  ensure
    body.respond_to?(:close) and body.close
  end

  # returns nil on success
  # :wait_readable/:wait_writable/:close for epoll
  def do_ccc
    @hs.response_start_sent = true
    wbuf = nil
    rv = nil
    CCC_RESPONSE_START.each do |buf|
      if wbuf
        wbuf << buf
      else
        case rv = kgio_trywrite(buf)
        when nil
          break
        when String
          buf = rv
        when :wait_writable, :wait_readable
          if self.class.output_buffering
            wbuf = buf.dup
            @state = Yahns::WbufStr.new(wbuf, :ccc_done)
            break
          else
            response_wait_write(rv) or return :close
          end
        end while true
      end
    end
    rv
  end

  # only used if input_buffering is true (not :lazy or false)
  # input_buffering==:lazy/false gives control to the app
  # returns nil on success
  # returns :close, :wait_writable, or :wait_readable
  def http_100_response(env)
    env.delete('HTTP_EXPECT'.freeze) =~ /\A100-continue\z/i or return
    buf = @hs.response_start_sent ? "100 Continue\r\n\r\nHTTP/1.1 ".freeze
                                  : "HTTP/1.1 100 Continue\r\n\r\n".freeze

    case rv = kgio_trywrite(buf)
    when String
      buf = rv
    when :wait_writable, :wait_readable
      if self.class.output_buffering
        @state = Yahns::WbufStr.new(buf, :r100_done)
        return rv
      else
        response_wait_write(rv) or return :close
      end
    else
      return rv
    end while true
  end

  # must be called before app dispatch, since the app can
  # do all sorts of nasty things to env
  def http_response_prep(env)
    [ env['REQUEST_METHOD'] == 'HEAD'.freeze, # hdr_only
      env['HTTP_VERSION'] == 'HTTP/1.1'.freeze ] # chunk_ok
  end
end
