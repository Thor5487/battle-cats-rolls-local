# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative '../yahns'

module Yahns::Daemon # :nodoc:
  # We don't do a lot of standard daemonization stuff:
  #   * umask is whatever was set by the parent process at startup
  #     and can be set in config.ru and config_file, so making it
  #     0000 and potentially exposing sensitive log data can be bad
  #     policy.
  #   * don't bother to chdir("/") here since yahns is designed to
  #     run inside APP_ROOT.  Yahns will also re-chdir() to
  #     the directory it was started in when being re-executed
  #     to pickup code changes if the original deployment directory
  #     is a symlink or otherwise got replaced.
  def self.daemon(yahns_server)
    $stdin.reopen("/dev/null")

    # We only start a new process group if we're not being reexecuted
    # and inheriting file descriptors from our parent
    if ENV['YAHNS_FD']
      # if we're inheriting, need to ensure this remains true so
      # SIGWINCH works when worker processes are in play
      yahns_server.daemon_pipe = true
    else
      # grandparent - reads pipe, exits when master is ready
      #  \_ parent  - exits immediately ASAP
      #      \_ yahns master - writes to pipe when ready

      # We cannot use Yahns::Sigevent (eventfd) here because we need
      # to detect EOF on unexpected death, not just read/write
      rd, wr = IO.pipe
      grandparent = $$
      if fork
        wr.close # grandparent does not write
      else
        rd.close # yahns master does not read
        Process.setsid
        exit if fork # parent dies now
      end

      if grandparent == $$
        # this will block until Server#join runs (or it dies)
        master_pid = (rd.readpartial(16) rescue nil).to_i
        unless master_pid > 1
          warn "master failed to start, check stderr log for details"
          exit!
        end
        exit
      else # yahns master process
        yahns_server.daemon_pipe = wr
      end
    end
    # $stderr/$stderr can/will be redirected separately in the Yahns config
  end
end
