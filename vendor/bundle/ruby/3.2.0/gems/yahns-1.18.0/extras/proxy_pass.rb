# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'time'
require 'socket'
require 'kgio'
require 'kcar' # gem install kcar
require 'rack/request'
require 'thread'
require 'timeout'

# Totally synchronous and Rack 1.1-compatible.  See Yahns::ProxyPass for
# the rewritten version which takes advantage of rack.hijack and uses
# the internal non-blocking I/O facilities in yahns.  yahns may have to
# grow a supported API for that...
#
# For now, we this blocks a worker thread; fortunately threads are reasonably
# cheap on GNU/Linux...
class ProxyPass # :nodoc:
  class ConnPool
    def initialize
      @mtx = Mutex.new
      @objs = []
    end

    def get
      @mtx.synchronize { @objs.pop }
    end

    def put(obj)
      @mtx.synchronize { @objs << obj }
    end
  end

  class UpstreamSocket < Kgio::Socket # :nodoc:
    attr_writer :expiry

    # called automatically by kgio_read!
    def wait_readable(timeout = nil)
      super(timeout || wait_time)
    end

    def wait_time
      tout = @expiry ? @expiry - Time.now : @timeout
      raise Timeout::Error, "request timed out", [] if tout < 0
      tout
    end

    def readpartial(bytes, buf = Thread.current[:proxy_pass_buf] ||= ''.dup)
      case rv = kgio_read!(bytes, buf)
      when String
        @expiry += @timeout # bump expiry when we succeed
      end
      rv
    end

    def req_write(buf, timeout)
      @timeout = timeout
      @expiry = Time.now + timeout
      case rv = kgio_trywrite(buf)
      when :wait_writable
        wait_writable(wait_time)
      when nil
        return
      when String
        buf = rv
      end while true
    end
  end # class UpstreamSocket

  class UpstreamResponse < Kcar::Response # :nodoc:
    # Called by the Rack server at the end of a successful response
    def close
      reusable = @parser.keepalive? && @parser.body_eof?
      super
      @pool.put(self) if reusable
      nil
    end

    # req is just a string buffer of HTTP headers
    def req_write(req, timeout)
      @sock.req_write(req, timeout)
    end

    # returns true if the socket is still alive, nil if dead
    def sock_alive?
      @reused = (:wait_readable == (@sock.kgio_tryread(1) rescue nil)) ?
                true : @sock.close
    end

    # returns true if the socket was reused and thus retryable
    def fail_retryable?
      @sock.close
      @reused
    end

    def initialize(sock, pool)
      super(sock)
      @reused = false
      @pool = pool
    end
  end # class UpstreamResponse

  # take a responder from the pool, we'll add the object back to the
  # pool in UpstreamResponse#close
  def responder_get
    while obj = @pool.get
      return obj if obj.sock_alive?
    end

    UpstreamResponse.new(UpstreamSocket.start(@sockaddr), @pool)
  end

  def initialize(dest, timeout = 5)
    case dest
    when %r{\Aunix:([^:]+)(?::(/.*))?\z}
      path = $2
      @sockaddr = Socket.sockaddr_un($1)
    when %r{\Ahttp://([^/]+)(/.*)?\z}
      path = $2
      host, port = $1.split(':')
      @sockaddr = Socket.sockaddr_in(port || 80, host)
    else
      raise ArgumentError, "destination must be an HTTP URL or unix: path"
    end
    init_path_vars(path)
    @pool = ConnPool.new
    @timeout = timeout
  end

  def init_path_vars(path)
    path ||= '$fullpath'
    # methods from Rack::Request we want:
    allow = %w(fullpath host_with_port host port url path)
    want = path.scan(/\$(\w+)/).flatten! || []
    diff = want - allow
    diff.empty? or
             raise ArgumentError, "vars not allowed: #{diff.uniq.join(' ')}"

    # kill leading slash just in case...
    @path = path.gsub(%r{\A/(\$(?:fullpath|path))}, '\1')
  end

  def call(env)
    request_method = env['REQUEST_METHOD']
    req = Rack::Request.new(env)
    path = @path.gsub(/\$(\w+)/) { req.__send__($1) }
    req = "#{request_method} #{path} HTTP/1.1\r\n" \
          "X-Forwarded-For: #{env["REMOTE_ADDR"]}\r\n".dup

    # pass most HTTP_* headers through as-is
    chunked = false
    env.each do |key, val|
      %r{\AHTTP_(\w+)\z} =~ key or next
      key = $1
      next if %r{\A(?:VERSION|CONNECTION|KEEP_ALIVE|X_FORWARDED_FOR)} =~ key
      chunked = true if %r{\ATRANSFER_ENCODING} =~ key && val =~ /\bchunked\b/i
      key.tr!("_", "-")
      req << "#{key}: #{val}\r\n"
    end

    # special cases which Rack does not prefix:
    ctype = env["CONTENT_TYPE"] and req << "Content-Type: #{ctype}\r\n"
    clen = env["CONTENT_LENGTH"] and req << "Content-Length: #{clen}\r\n"
    req << "\r\n"

    # get an open socket and send the headers
    ures = responder_get
    ures.req_write(req, @timeout)

    # send the request body if there was one
    send_body(env["rack.input"], ures, chunked) if chunked || clen

    # wait for the response here
    _, header, body = res = ures.rack

    # don't let the upstream Connection and Keep-Alive headers leak through
    header.delete_if do |k,_|
      k =~ /\A(?:Connection|Keep-Alive)\z/i
    end

    case request_method
    when "HEAD"
      # kcar doesn't know if it's a HEAD or GET response, and HEAD
      # responses have Content-Length in it which fools kcar...
      body.parser.body_bytes_left = 0
      res[1] = header.dup
      body.close # clobbers original header
      res[2] = body = []
    end
    res
  rescue => e
    retry if ures && ures.fail_retryable? && request_method != "POST"
    if defined?(Yahns::Log)
      logger = env['rack.logger'] and
        Yahns::Log.exception(logger, 'proxy_pass', e)
    end
    [ 502, { 'Content-Length' => '0', 'Content-Type' => 'text/plain' }, [] ]
  end

  def send_body(input, ures, chunked)
    buf = Thread.current[:proxy_pass_buf] ||= ''.dup

    if chunked # unlikely
      while input.read(16384, buf)
        buf.replace("#{buf.size.to_s(16)}\r\n#{buf}\r\n")
        ures.req_write(buf, @timeout)
      end
      ures.req_write("0\r\n\r\n", @timeout)
    else # common if we hit uploads
      while input.read(16384, buf)
        ures.req_write(buf, @timeout)
      end
    end
  end
end
