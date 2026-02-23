# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# this is only meant for Yahns::Server
module Yahns::SocketHelper # :nodoc:

  # Linux got SO_REUSEPORT in 3.9, BSDs have had it for ages
  def so_reuseport
    if defined?(Socket::SO_REUSEPORT)
      Socket::SO_REUSEPORT
    elsif RUBY_PLATFORM.include?('linux')
      15 # only tested on x86_64 and i686
    else
      nil
    end
  end

  def set_server_sockopt(sock, opt)
    opt = {backlog: 1024}.merge!(opt)
    sock.close_on_exec = true # needed for inherited sockets

    TCPSocket === sock and sock.setsockopt(:IPPROTO_TCP, :TCP_NODELAY, 1)
    sock.setsockopt(:SOL_SOCKET, :SO_KEEPALIVE, 1)

    if opt[:rcvbuf] || opt[:sndbuf]
      log_buffer_sizes(sock, "before: ")
      { SO_RCVBUF: :rcvbuf, SO_SNDBUF: :sndbuf }.each do |optname,cfgname|
        val = opt[cfgname] and sock.setsockopt(:SOL_SOCKET, optname, val)
      end
      log_buffer_sizes(sock, " after: ")
    end
    sock.listen(opt[:backlog])
  rescue => e
    Yahns::Log.exception(@logger, "#{sock_name(sock)} #{opt.inspect}", e)
  end

  def log_buffer_sizes(sock, pfx = '')
    rcvbuf = sock.getsockopt(:SOL_SOCKET, :SO_RCVBUF).int
    sndbuf = sock.getsockopt(:SOL_SOCKET, :SO_SNDBUF).int
    @logger.info("#{pfx}#{sock_name(sock)} rcvbuf=#{rcvbuf} sndbuf=#{sndbuf}")
  rescue # TODO: get this fixed in rbx
  end

  # creates a new server, socket. address may be a HOST:PORT or
  # an absolute path to a UNIX socket.  address can even be a Socket
  # object in which case it is immediately returned
  def bind_listen(address, opt)
    return address unless String === address
    opt ||= {}

    sock = if address[0] == ?/
      if File.exist?(address)
        if File.socket?(address)
          begin
            UNIXSocket.new(address).close
            # fall through, try to bind(2) and fail with EADDRINUSE
            # (or succeed from a small race condition we can't sanely avoid).
          rescue Errno::ECONNREFUSED
            @logger.info "unlinking existing socket=#{address}"
            File.unlink(address)
          end
        else
          raise ArgumentError,
                "socket=#{address} specified but it is not a socket!"
        end
      end
      old_umask = File.umask(opt[:umask] || 0)
      begin
        Yahns::UNIXServer.new(address)
      ensure
        File.umask(old_umask)
      end
    elsif /\A\[([a-fA-F0-9:]+)\]:(\d+)\z/ =~ address
      new_tcp_server($1, $2.to_i, opt.merge(ipv6: true))
    elsif /\A(\d+\.\d+\.\d+\.\d+):(\d+)\z/ =~ address
      new_tcp_server($1, $2.to_i, opt)
    else
      raise ArgumentError, "Don't know how to bind: #{address}"
    end
    set_server_sockopt(sock, opt)
    sock
  end

  def new_tcp_server(addr, port, opt)
    sock = Socket.new(opt[:ipv6] ? :INET6 : :INET, :STREAM, 0)
    if opt.key?(:ipv6only)
      sock.setsockopt(:IPPROTO_IPV6, :IPV6_V6ONLY, opt[:ipv6only] ? 1 : 0)
    end
    sock.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, 1)

    begin
      sock.setsockopt(:SOL_SOCKET, so_reuseport, 1)
    rescue => e
      name = sock_name(sock)
      @logger.warn("failed to set SO_REUSEPORT on #{name}: #{e.message}")
    end if opt[:reuseport]

    sock.bind(Socket.pack_sockaddr_in(port, addr))
    sock.autoclose = false

    if ssl_ctx = opt[:ssl_ctx]
      Yahns::OpenSSLServer.wrap(sock.fileno, ssl_ctx)
    else
      Yahns::TCPServer.for_fd(sock.fileno)
    end
  end

  # returns rfc2732-style (e.g. "[::1]:666") addresses for IPv6
  def tcp_name(sock)
    port, addr = Socket.unpack_sockaddr_in(sock.getsockname)
    addr.include?(':') ? "[#{addr}]:#{port}" : "#{addr}:#{port}"
  end

  # Returns the configuration name of a socket as a string.  sock may
  # be a string value, in which case it is returned as-is
  # Warning: TCP sockets may not always return the name given to it.
  def sock_name(sock)
    case sock
    when String then sock
    when UNIXServer
      Socket.unpack_sockaddr_un(sock.getsockname)
    when TCPServer
      tcp_name(sock)
    when Socket
      begin
        tcp_name(sock)
      rescue ArgumentError
        Socket.unpack_sockaddr_un(sock.getsockname)
      end
    else
      raise ArgumentError, "Unhandled class #{sock.class}: #{sock.inspect}"
    end
  end

  # casts a given Socket to be a TCPServer or UNIXServer
  def server_cast(sock, opts)
    sock.autoclose = false
    begin
      Socket.unpack_sockaddr_in(sock.getsockname)
      if ssl_ctx = opts[:ssl_ctx]
        Yahns::OpenSSLServer.wrap(sock.fileno, ssl_ctx)
      else
        Yahns::TCPServer.for_fd(sock.fileno)
      end
    rescue ArgumentError
      Yahns::UNIXServer.for_fd(sock.fileno)
    end
  end
end
