# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'thread'

# only initialize this after forking, this is highly volatile and won't
# be able to share data across processes at all.
# This is really a singleton

class Yahns::Fdmap # :nodoc:
  def initialize(logger, client_expire_threshold)
    @logger = logger

    if Float === client_expire_threshold
      client_expire_threshold *= Process.getrlimit(:NOFILE)[0]
    elsif client_expire_threshold < 0
      client_expire_threshold = Process.getrlimit(:NOFILE)[0] +
                                client_expire_threshold
    end
    @client_expire_threshold = client_expire_threshold.to_i

    # This is an array because any sane OS will frequently reuse FDs
    # to keep this tightly-packed and favor lower FD numbers
    # (consider select(2) performance (not that we use select))
    # An (unpacked) Hash (in MRI) uses 5 more words per entry than an Array,
    # and we should expect this array to have around 60K elements
    @fdmap_ary = []
    @fdmap_mtx = Mutex.new
    @last_expire = 0.0
    @count = 0
  end

  # Yes, we call IO#close inside the lock(!)
  #
  # We don't want to race with __expire.  Theoretically, a Ruby
  # implementation w/o GVL may end up issuing shutdown(2) on the same fd
  # as one which got accept-ed (a brand new IO object) so we must prevent
  # IO#close in worker threads from racing with any threads which may run
  # __expire
  #
  # We must never, ever call this while it is capable of being on the
  # epoll ready list and returnable by epoll_wait.  So we can only call
  # this on objects which were epoll_ctl-ed with EPOLLONESHOT (and now
  # retrieved).
  def sync_close(io)
    @fdmap_mtx.synchronize do
      @count -= 1
      io.close
    end
  end

  # called immediately after accept()
  def add(io)
    fd = io.fileno
    @fdmap_mtx.synchronize do
      if (@count += 1) > @client_expire_threshold
        __expire(nil)
      end
      @fdmap_ary[fd] = io
    end
  end

  # used by proxy to re-enable an existing client
  def remember(io)
    fd = io.fileno
    @fdmap_mtx.synchronize do
      @count += 1
      @fdmap_ary[fd] = io
    end
  end

  # this is only called in Errno::EMFILE/Errno::ENFILE situations
  # and graceful shutdown
  def desperate_expire(timeout)
    @fdmap_mtx.synchronize { __expire(timeout) }
  end

  # only called on hijack
  def forget(io)
    fd = io.fileno
    @fdmap_mtx.synchronize do
      # prevent rack.hijacked IOs from being expired by us
      @fdmap_ary[fd] = nil
      @count -= 1
    end
  end

  # expire a bunch of idle clients and register the current one
  # We should not be calling this too frequently, it is expensive
  # This is called while @fdmap_mtx is held
  def __expire(timeout)
    return 0 if @count == 0
    nr = 0
    now = Yahns.now
    (now - @last_expire) >= 1.0 or return @count # don't expire too frequently

    # @fdmap_ary may be huge, so always expire a bunch at once to
    # avoid getting to this method too frequently
    @fdmap_ary.each do |c|
      c.respond_to?(:yahns_expire) or next
      ctimeout = c.class.client_timeout
      tout = (timeout && timeout < ctimeout) ? timeout : ctimeout
      nr += c.yahns_expire(tout)
    end

    @last_expire = Yahns.now
    if nr != 0
      msg = timeout ? "timeout=#{timeout}" : "client_timeout"
      @logger.info("dropping #{nr} of #@count clients for #{msg}")
    end
    @count
  end

  # used for graceful shutdown
  def size
    @fdmap_mtx.synchronize { @count }
  end
end
