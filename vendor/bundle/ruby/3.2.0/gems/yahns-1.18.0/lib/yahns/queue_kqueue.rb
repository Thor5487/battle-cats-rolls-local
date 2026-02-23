# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
#
# This is the dangerous, low-level kqueue interface for sleepy_penguin
# It is safe as long as you're aware of all potential concurrency
# issues given multithreading, GC, and kqueue itself.
class Yahns::Queue < SleepyPenguin::Kqueue::IO # :nodoc:
  include SleepyPenguin
  attr_accessor :fdmap # Yahns::Fdmap

  # public
  QEV_QUIT = nil # Level Trigger for QueueQuitter
  QEV_RD = EvFilt::READ
  QEV_WR = EvFilt::WRITE

  ADD_ONESHOT = Ev::ADD | Ev::ONESHOT # private

  # for HTTP and HTTPS servers, we rely on the io writing to us, first
  # flags: QEV_RD/QEV_WR (usually QEV_RD)
  def queue_add(io, flags)
    # order is very important here, this thread cannot do anything with
    # io once we've issued kevent EV_ADD because another thread may use it
    @fdmap.add(io)
    fflags = ADD_ONESHOT
    if flags == QEV_QUIT
      fflags = Ev::ADD
      flags = QEV_WR
    end
    kevent(Kevent[io.fileno, flags, fflags, 0, 0, io])
  end

  def queue_mod(io, flags)
    kevent(Kevent[io.fileno, flags, ADD_ONESHOT, 0, 0, io])
  end

  def thr_init
    Thread.current[:yahns_rbuf] = ''.dup
    Thread.current[:yahns_fdmap] = @fdmap
    Thread.current[:yahns_queue] = self
  end

  # returns an infinitely running thread
  def worker_thread(logger, max_events)
    Thread.new do
      thr_init
      begin
        kevent(nil, max_events) do |_,_,_,_,_,io| # don't care for flags for now
          next if io.closed?
          # Note: we absolutely must not do anything with io after
          # we've called kevent(...,EV_ADD) on it, io is exclusive to this
          # thread only until kevent(...,EV_ADD) is called on it.
          case rv = io.yahns_step
          when :wait_readable
            kevent(Kevent[io.fileno, QEV_RD, ADD_ONESHOT, 0, 0, io])
          when :wait_writable
            kevent(Kevent[io.fileno, QEV_WR, ADD_ONESHOT, 0, 0, io])
          when :ignore # only used by rack.hijack
            # we cannot EV_DELETE after hijacking, the hijacker
            # may have already closed it  Likewise, io.fileno is not
            # expected to work, so we had to erase it from fdmap before hijack
          when nil, :close
            # this must be the ONLY place where we call IO#close on
            # things that got inside the queue AND fdmap
            @fdmap.sync_close(io)
          else
            raise "BUG: #{io.inspect}#yahns_step returned: #{rv.inspect}"
          end
        end
      rescue StandardError, LoadError, SyntaxError => e
        break if closed? # can still happen due to shutdown_timeout
        Yahns::Log.exception(logger, 'queue loop', e)
      end while true
    end
  end
end
