# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (see COPYING for details)
# frozen_string_literal: true
require_relative 'client_expire_tcpi'
require_relative 'client_expire_generic'
module Yahns::Acceptor # :nodoc:
  def __ac_quit_done?
    @thrs.delete_if do |t|
      begin
        t.join(0.01)
      rescue
        ! t.alive?
      end
    end
    return false if @thrs[0]
    close
    true
  end

  # just keep looping this on every acceptor until the associated thread dies
  def ac_quit
    unless defined?(@thrs) # acceptor has not started yet, freshly inherited
      close
      return true
    end
    @quit = true
    return true if __ac_quit_done?

    @thrs.each do
      begin
        # try to connect to kick it out of the blocking accept() syscall
        killer = Kgio::Socket.start(getsockname)
        killer.kgio_write("G") # first byte of "GET / HTTP/1.0\r\n\r\n"
      ensure
        killer.close if killer
      end
    end
    false # now hope __ac_quit_done? is true next time around
  rescue SystemCallError
    return __ac_quit_done?
  end

  def spawn_acceptor(nr, logger, client_class)
    @quit = false
    @thrs = nr.times.map do
      Thread.new do
        queue = client_class.queue
        accept_flags = Kgio::SOCK_NONBLOCK | Kgio::SOCK_CLOEXEC
        qev_flags = client_class.superclass::QEV_FLAGS
        begin
          # We want the accept/accept4 syscall to be _blocking_
          # so it can distribute work evenly between processes
          if client = kgio_accept(client_class, accept_flags)
            client.yahns_init

            # it is not safe to touch client in this thread after this,
            # a worker thread may grab client right away
            queue.queue_add(client, qev_flags)
          end
        rescue Errno::EMFILE, Errno::ENFILE => e
          logger.error("#{e.message}, consider raising open file limits")
          queue.fdmap.desperate_expire(5)
          sleep 1 # let other threads do some work
        rescue => e
          Yahns::Log.exception(logger, "accept loop", e)
        end until @quit
      end
    end
  end

  def expire_mod
    (TCPServer === self && Yahns.const_defined?(:ClientExpireTCPI)) ?
     Yahns::ClientExpireTCPI : Yahns::ClientExpireGeneric
  end
end
