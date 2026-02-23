# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# this is to be included into a Kgio::Socket-derived class
# this requires Ruby 2.1 and later for "exception: false"
module Yahns::OpenSSLClient # :nodoc:
  def self.included(cls)
    # Forward these methods to OpenSSL::SSL::SSLSocket so hijackers
    # can rely on stdlib methods instead of ugly kgio stuff that
    # we hope to phase out.
    # This is a bit weird, since OpenSSL::SSL::SSLSocket wraps
    # our actual socket, too, so we must take care to not blindly
    # use method_missing and cause infinite recursion
    %w(sync= read write readpartial write_nonblock read_nonblock
       print printf puts gets readlines readline getc
       readchar ungetc eof eof? << flush
       sysread syswrite).map!(&:to_sym).each do |m|
      cls.__send__(:define_method, m) { |*a| @ssl.__send__(m, *a) }
    end

    # block captures, ugh, but nobody really uses them
    %w(each each_line each_byte).map!(&:to_sym).each do |m|
      cls.__send__(:define_method, m) { |*a, &b| @ssl.__send__(m, *a, &b) }
    end
  end

  # this is special, called during IO initialization in Ruby
  def sync
    defined?(@ssl) ? @ssl.sync : super
  end

  def yahns_init_ssl(ssl_ctx)
    @need_accept = true
    @ssl = OpenSSL::SSL::SSLSocket.new(self, ssl_ctx)
    @ssl_blocked = nil
  end

  def kgio_trywrite(buf)
    len = buf.bytesize
    return if len == 0

    case @ssl_blocked
    when nil # likely
      buf = @ssl_blocked = buf.dup
    when Exception
      raise @ssl_blocked
    when String
      if @ssl_blocked != buf
        pfx = object_id
        warn("#{pfx} BUG: ssl_blocked != buf\n" \
             "#{pfx} ssl_blocked=#{@ssl_blocked.inspect}\n" \
             "#{pfx} buf=#{buf.inspect}\n")
        raise 'BUG: ssl_blocked} != buf'
      end
    end

    case rv = @ssl.write_nonblock(buf, exception: false)
    when :wait_readable, :wait_writable
      rv # do not clear ssl_blocked
    when Integer
      @ssl_blocked = len == rv ? nil : buf.byteslice(rv, len - rv)
    end
  rescue SystemCallError => e # ECONNRESET/EPIPE
    e.set_backtrace([])
    raise(@ssl_blocked = e)
  end

  def kgio_trywritev(buf)
    kgio_trywrite(buf.join)
  end

  def kgio_syssend(buf, flags)
    kgio_trywrite(buf)
  end

  def kgio_tryread(len, buf)
    if @need_accept
      # most protocols require read before write, so we start the negotiation
      # process here:
      case rv = accept_nonblock(@ssl)
      when :wait_readable, :wait_writable, nil
        return rv
      end
      @need_accept = false
    end
    @ssl.read_nonblock(len, buf, exception: false)
  end

  def trysendio(io, offset, count)
    return 0 if count == 0

    case buf = @ssl_blocked
    when nil
      buf = do_pread(io, count, offset) or return # nil for EOF
      buf = @ssl_blocked = buf.dup
    when Exception
      raise buf
    # when String # just use it as-is
    end

    # call write_nonblock directly since kgio_trywrite allocates
    # an unnecessary string
    len = buf.size
    case rv = @ssl.write_nonblock(buf, exception: false)
    when :wait_readable, :wait_writable
      return rv # do not clear ssl_blocked
    when Integer
      @ssl_blocked = len == rv ? nil : buf.byteslice(rv, len - rv)
    end
    rv
  rescue SystemCallError => e # ECONNRESET/EPIPE
    e.set_backtrace([])
    raise(@ssl_blocked = e)
  end

  def shutdown # we never call this with a how=SHUT_* arg
    @ssl.sysclose
  end

  alias trysendfile trysendio

  def close
    @ssl.close # flushes SSLSocket
    super # IO#close
  end

  if RUBY_VERSION.to_f >= 2.3
    def accept_nonblock(ssl)
      ssl.accept_nonblock(exception: false)
    end
  else
    def accept_nonblock(ssl)
      ssl.accept_nonblock
    rescue IO::WaitReadable
      :wait_readable
    rescue IO::WaitWritable
      :wait_writable
    rescue OpenSSL::SSL::SSLError
      nil
    end
  end
end
