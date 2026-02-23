# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
class Yahns::Worker # :nodoc:
  attr_accessor :nr
  attr_reader :to_io

  def initialize(nr)
    @nr = nr
    @to_io, @wr = Kgio::Pipe.new

    begin
      # F_SETPIPE_SZ = 1031, PAGE_SIZE = 4096
      # (fcntl will handle minimum size on platforms where PAGE_SIZE > 4096)
      @to_io.fcntl(1031, 4096)
    rescue SystemCallError
      # old kernel (EINVAL, EPERM)
    end if RUBY_PLATFORM =~ /\blinux\b/
  end

  def atfork_child
    @wr = @wr.close # nil @wr to save space in worker process
  end

  def atfork_parent
    @to_io = @to_io.close
    self
  end

  # used in the worker process.
  # This causes the worker to gracefully exit if the master
  # dies unexpectedly.
  def yahns_step
    case buf = @to_io.kgio_tryread(4)
    when String
      # unpack the buffer and trigger the signal handler
      signum = buf.unpack('l')
      fake_sig(signum[0])
      # keep looping, more signals may be queued
    when nil # EOF: master died, but we are at a safe place to exit
      fake_sig(:QUIT)
      @to_io.close
      return :ignore
    when :wait_readable # keep waiting
      return :ignore
    end while true # loop, as multiple signals may be sent
  end

  # worker objects may be compared to just plain Integers
  def ==(other_nr) # :nodoc:
    @nr == other_nr
  end

  # call a signal handler immediately without triggering EINTR
  # We do not use the more obvious Process.kill(sig, $$) here since
  # that signal delivery may be deferred.  We want to avoid signal delivery
  # while the Rack app.call is running because some database drivers
  # (e.g. ruby-pg) may cancel pending requests.
  def fake_sig(sig) # :nodoc:
    old_cb = trap(sig, "IGNORE")
    old_cb.call
  ensure
    trap(sig, old_cb)
  end

  # master sends fake signals to children
  def soft_kill(signum) # :nodoc:
    # writing and reading 4 bytes on a pipe is atomic on all POSIX platforms
    # Do not care in the odd case the buffer is full, here.
    @wr.kgio_trywrite([signum].pack('l'))
  rescue Errno::EPIPE
    # worker will be reaped soon
  end
end
