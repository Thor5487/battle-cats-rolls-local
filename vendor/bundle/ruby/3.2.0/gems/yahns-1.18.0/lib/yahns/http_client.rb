# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
begin
  raise LoadError, 'SENDFILE_BROKEN env set' if ENV['SENDFILE_BROKEN']
  require 'sendfile'
rescue LoadError
end

class Yahns::HttpClient < Kgio::Socket # :nodoc:
  NULL_IO = StringIO.new(''.dup) # :nodoc:

  include Yahns::HttpResponse
  QEV_FLAGS = Yahns::Queue::QEV_RD # used by acceptor

  # called from acceptor thread
  def yahns_init
    @hs = Unicorn::HttpRequest.new
    @state = :headers # :body, :trailers, :pipelined, Wbuf, StreamFile
    @input = nil
  end

  # use if writes are deferred by buffering, this return value goes to
  # the main epoll/kqueue worker loop
  # returns :wait_readable, :wait_writable, or nil
  def step_write
    case rv = @state.wbuf_flush(self)
    when :wait_writable, :wait_readable
      return rv # tell epoll/kqueue to wait on this more
    when :ignore # :ignore on hijack, @state already set in hijack_cleanup
      return :ignore
    when Yahns::StreamFile
      @state = rv # continue looping
    when true, false # done
      return http_response_done(rv)
    when :ccc_done, :r100_done
      @state = rv
      return :wait_writable
    else
      raise "BUG: #{@state.inspect}#wbuf_flush returned #{rv.inspect}"
    end while true
  end

  # used only with "input_buffering true"
  def mkinput_preread
    k = self.class
    len = @hs.content_length
    mbs = k.client_max_body_size
    if mbs && len && len > mbs
      raise Unicorn::RequestEntityTooLargeError,
            "Content-Length:#{len} too large (>#{mbs})", []
    end
    @state = :body
    @input = k.tmpio_for(len, @hs.env)

    rbuf = Thread.current[:yahns_rbuf]
    @hs.filter_body(rbuf, @hs.buf)
    @input.write(rbuf)
  end

  def input_ready
    empty_body = 0 == @hs.content_length
    k = self.class
    case k.input_buffering
    when true
      rv = http_100_response(@hs.env) and return rv

      # common case is an empty body
      return NULL_IO if empty_body

      # content_length is nil (chunked) or len > 0
      mkinput_preread # keep looping
      false
    else # :lazy, false
      empty_body ? NULL_IO : (@input = k.mkinput(self, @hs))
    end
  end

  # returns true if we want to keep looping on this
  # returns :wait_readable/wait_writable/nil to yield back to epoll
  def fill_body(rsize, rbuf)
    case rv = kgio_tryread(rsize, rbuf)
    when String
      @hs.filter_body(rbuf, @hs.buf << rbuf)
      @input.write(rbuf)
      true # keep looping on kgio_tryread (but check body_eof? first)
    when :wait_readable, :wait_writable
      rv # have epoll/kqueue wait for more
    when nil # unexpected EOF
      @input.close # nil
    end
  end

  # returns true if we are ready to dispatch the app
  # returns :wait_readable/wait_writable/nil to yield back to epoll
  def read_trailers(rsize, rbuf)
    case rv = kgio_tryread(rsize, rbuf)
    when String
      if @hs.add_parse(rbuf)
        @input.rewind
        return true
      end
      # keep looping on kgio_tryread...
    when :wait_readable, :wait_writable
      return rv # wait for more
    when nil # unexpected EOF
      return @input.close # nil
    end while true
  end

  # the main entry point of the epoll/kqueue worker loop
  def yahns_step
    # always write unwritten data first if we have any
    return step_write if Yahns::WbufCommon === @state

    # only read if we had nothing to write in this event loop iteration
    k = self.class
    rbuf = Thread.current[:yahns_rbuf] # running under spawn_worker_threads

    case @state
    when :pipelined
      if @hs.parse
        case input = input_ready
        when :wait_readable, :wait_writable, :close then return input
        when false # keep looping on @state
        else
          return app_call(input)
        end
        # @state == :body if we get here point (input_ready -> mkinput_preread)
      else
        @state = :headers
      end
      # continue to outer loop
    when :headers
      case rv = kgio_tryread(k.client_header_buffer_size, rbuf)
      when String
        if @hs.add_parse(rv)
          case input = input_ready
          when :wait_readable, :wait_writable, :close then return input
          when false then break # to outer loop to reevaluate @state == :body
          else
            return app_call(input)
          end
        end
        # keep looping on kgio_tryread
      when :wait_readable, :wait_writable, nil
        return rv
      end while true
    when :body
      if @hs.body_eof?
        if @hs.content_length || @hs.parse # hp.parse == trailers done!
          @input.rewind
          return app_call(@input)
        else # possible Transfer-Encoding:chunked, keep looping
          @state = :trailers
        end
      else
        rv = fill_body(k.client_body_buffer_size, rbuf)
        return rv unless true == rv
      end
    when :trailers
      rv = read_trailers(k.client_header_buffer_size, rbuf)
      return true == rv ? app_call(@input) : rv
    when :ccc_done # unlikely
      return app_call(nil)
    when :r100_done # unlikely
      rv = r100_done
      return rv unless rv == true
      raise "BUG: body=#@state " if @state != :body
      # @state == :body, keep looping
    end while true # outer loop
  rescue => e
    handle_error(e)
  end

  # only called when buffering slow clients
  # returns :wait_readable, :wait_writable, :ignore, or nil for epoll
  # returns true to keep looping inside yahns_step
  def r100_done
    k = self.class
    case k.input_buffering
    when true
      empty_body = 0 == @hs.content_length
      # common case is an empty body
      return app_call(NULL_IO) if empty_body

      # content_length is nil (chunked) or len > 0
      mkinput_preread # keep looping (@state == :body)
      true
    else # :lazy, false
      env = @hs.env
      opt = http_response_prep(env)
      res = k.app.call(env)
      return :ignore if app_hijacked?(env, res)
      http_response_write(res, opt)
    end
  end

  def app_call(input)
    env = @hs.env
    k = self.class

    # input is nil if we needed to wait for writability with
    # check_client_connection
    if input
      env['REMOTE_ADDR'] = @kgio_addr
      env['rack.hijack'] = self
      env['rack.input'] = input

      if k.check_client_connection && @hs.headers?
        rv = do_ccc and return rv
      end
    end

    env.merge!(k.app_defaults)

    # workaround stupid unicorn_http parser behavior when it parses HTTP_HOST
    if env['HTTPS'] == 'on'.freeze &&
        env['HTTP_HOST'] &&
        env['SERVER_PORT'] == '80'.freeze
      env['SERVER_PORT'] = '443'.freeze
    end

    opt = http_response_prep(env)
    # run the rack app
    res = k.app.call(env)
    return :ignore if app_hijacked?(env, res)
    if res[0].to_i == 100
      rv = http_100_response(env) and return rv
      res = k.app.call(env)
    end

    # this returns :wait_readable, :wait_writable, :ignore, or nil:
    http_response_write(res, opt)
  end

  # used by StreamInput (and thus TeeInput) for input_buffering {false|:lazy}
  def yahns_read(bytes, buf)
    case rv = kgio_tryread(bytes, buf)
    when String, nil
      return rv
    when :wait_readable
      wait_readable(self.class.client_timeout) or
        raise Yahns::ClientTimeout, "waiting for read", []
    when :wait_writable
      wait_writable(self.class.client_timeout) or
        raise Yahns::ClientTimeout, "waiting for write", []
    end while true
  end

  # allow releasing some memory if rack.hijack is used
  # n.b. we no longer issue EPOLL_CTL_DEL because it becomes more expensive
  # (and complicated) as our hijack support will allow "un-hijacking"
  # the socket.
  def hijack_cleanup
    # prevent socket from holding process exit up
    Thread.current[:yahns_fdmap].forget(self)
    @state = :ignore
    @input = nil # keep env["rack.input"] accessible, though
  end

  # this is the env["rack.hijack"] callback exposed to the Rack app
  def call
    hijack_cleanup
    @hs.env['rack.hijack_io'] = self
  end

  def response_hijacked(fn)
    hijack_cleanup
    fn.call(self)
    :ignore
  end

  # if we get any error, try to write something back to the client
  # assuming we haven't closed the socket, but don't get hung up
  # if the socket is already closed or broken.  We'll always return
  # nil to ensure the socket is closed at the end of this function
  def handle_error(e)
    code = case e
    when EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::ENOTCONN,
         Errno::ETIMEDOUT,Errno::EHOSTUNREACH
      return # don't send response, drop the connection
    when Yahns::ClientTimeout
      408
    when Unicorn::RequestURITooLongError
      414
    when Unicorn::RequestEntityTooLargeError
      413
    when Unicorn::HttpParserError # try to tell the client they're bad
      400
    else
      n = 500
      case e.class.to_s
      when 'OpenSSL::SSL::SSLError'
        if e.message.include?('wrong version number')
          n = nil
          e.set_backtrace([])
        end
      end
      Yahns::Log.exception(@hs.env["rack.logger"], "app error", e)
      n
    end
    kgio_trywrite(err_response(code)) if code
  rescue
  ensure
    shutdown rescue nil
    return # always drop the connection on uncaught errors
  end

  def app_hijacked?(env, res)
    return false unless env.include?('rack.hijack_io'.freeze)
    res[2].close if res && res[2].respond_to?(:close)
    true
  end

  def do_pread(io, count, offset)
    count = 0x4000 if count > 0x4000
    buf = Thread.current[:yahns_sfbuf] ||= ''.dup
    if io.respond_to?(:pread)
      io.pread(count, offset, buf)
    else
      io.pos = offset
      io.read(count, buf)
    end
  rescue EOFError
    nil
  end

  def trysendio(io, offset, count)
    return 0 if count == 0
    str = do_pread(io, count, offset) or return # nil for EOF
    n = 0
    case rv = kgio_trywrite(str)
    when String # partial write, keep trying
      n += (str.size - rv.size)
      str = rv
    when :wait_writable, :wait_readable
      return n > 0 ? n : rv
    when nil
      return n + str.size # yay!
    end while true
  end

  alias trysendfile trysendio unless IO.instance_methods.include?(:trysendfile)
end
