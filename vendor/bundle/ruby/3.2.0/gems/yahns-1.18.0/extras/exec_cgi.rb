# -*- encoding: binary -*-
# Copyright (C) 2013-2018 all contributors <yahns-public@yhbt.net>
# License: GPL-2.0+ <https://www.gnu.org/licenses/gpl-2.0.txt>
# frozen_string_literal: true
#
# if running under yahns, worker_processes is recommended to avoid conflicting
# with the SIGCHLD handler in yahns.

# Be careful if using Rack::Deflater, this needs the following commit
# (currently in rack.git, not yet in 1.5.2):
#  commit 7bda8d485b38403bf07f43793d37b66b7a8281d6
#  (delfater: ensure that parent body is always closed)
# Otherwise you will get zombies from HEAD requests which accept compressed
# responses.
#
# Usage in config.ru using cgit as an example:
#
#   use Rack::Chunked
#   # other Rack middlewares can go here...
#
#   # cgit: https://git.zx2c4.com/cgit/
#   run ExecCgi.new('/path/to/cgit.cgi', opts)
#
class ExecCgi
  class MyIO
    attr_writer :my_pid
    attr_writer :body_tip
    attr_reader :rd

    def initialize(rd)
      @rd = rd
    end

    def each
      buf = @body_tip
      yield buf unless buf.empty?

      case tmp = @rd.read_nonblock(8192, buf, exception: false)
      when :wait_readable
        @rd.wait_readable
      when nil
        break
      else # String
        yield tmp
      end while true
      self
    ensure
      # do this sooner, since the response body may be buffered, we want
      # to release our FD as soon as possible.
      close
    end

    def close
      # yahns will call this again after its done writing the response
      # body, so we must ensure its idempotent.
      # Note: this object (and any client-specific objects) will never
      # be shared across different threads, so we do not need extra
      # mutual exclusion here.
      return if @rd.closed?
      @rd.close
      begin
        Process.waitpid(@my_pid)
      rescue Errno::ECHILD
      end if defined?(@my_pid) && @my_pid
    end
  end

  PASS_VARS = %w(
    CONTENT_LENGTH
    CONTENT_TYPE
    AUTH_TYPE
    PATH_INFO
    PATH_TRANSLATED
    QUERY_STRING
    REMOTE_ADDR
    REMOTE_HOST
    REMOTE_IDENT
    REMOTE_USER
    REQUEST_METHOD
    SERVER_NAME
    SERVER_PORT
    SERVER_PROTOCOL
    SERVER_SOFTWARE
    SCRIPT_NAME
  )

  def initialize(*args)
    @env = Hash === args[0] ? args.shift : {}
    @args = args
    first = args[0] or
      raise ArgumentError, "need path to executable"
    first[0] == ?/ or args[0] = ::File.expand_path(first)
    File.executable?(args[0]) or
      raise ArgumentError, "#{args[0]} is not executable"
    @opts = Hash === args[-1] ? args.pop : {}
  end

  # Calls the app
  def call(env)
    env.delete('HTTP_PROXY') # ref: https://httpoxy.org/
    cgi_env = { "GATEWAY_INTERFACE" => "CGI/1.1" }
    PASS_VARS.each { |key| val = env[key] and cgi_env[key] = val }
    env.each { |key,val| cgi_env[key] = val if key =~ /\AHTTP_/ }

    rd, wr = IO.pipe
    io = MyIO.new(rd)
    errbody = io
    errbody.my_pid = spawn(cgi_env.merge!(@env), *@args,
                           @opts.merge(out: wr, close_others: true))
    wr.close

    begin
      head = rd.readpartial(8192)
      until head =~ /\r?\n\r?\n/
        tmp = rd.readpartial(8192)
        head << tmp
        tmp.clear
      end
      head, body = head.split(/\r?\n\r?\n/, 2)
      io.body_tip = body

      env["HTTP_VERSION"] ||= "HTTP/1.0" # stop Rack::Chunked for HTTP/0.9

      headers = Rack::Utils::HeaderHash.new
      prev = nil
      head.split(/\r?\n/).each do |line|
        case line
        when /^([A-Za-z0-9-]+):\s*(.*)$/ then headers[prev = $1] = $2
        when /^[ \t]/ then headers[prev] << "\n#{line}" if prev
        end
      end
      status = headers.delete("Status") || 200
      errbody = nil
      [ status, headers, io ]
    rescue EOFError
      [ 500, { "Content-Length" => "0", "Content-Type" => "text/plain" }, [] ]
    end
  ensure
    errbody.close if errbody
  end
end
