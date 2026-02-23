# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

module Yahns::ServerMP # :nodoc:
  EXIT_SIGS = [ :QUIT, :TERM, :INT ]

  def maintain_worker_count
    (off = @workers.size - @worker_processes) == 0 and return
    off < 0 and return spawn_missing_workers
    @workers.each_value do |worker|
      worker.nr >= @worker_processes and worker.soft_kill(Signal.list["QUIT"])
    end
  end

  # fakes delivery of a signal to each worker
  def soft_kill_each_worker(sig)
    sig = Signal.list[sig]
    @workers.each_value { |worker| worker.soft_kill(sig) }
  end

  # this is the first thing that runs after forking in a child
  # gets rid of stuff the worker has no business keeping track of
  # to free some resources and drops all sig handlers.
  # traps for USR1, USR2, and HUP may be set in the after_fork Proc
  # by the user.
  def worker_atfork_internal(worker)
    worker.atfork_child

    # daemon_pipe may be true for non-initial workers
    @daemon_pipe = @daemon_pipe.close if @daemon_pipe.respond_to?(:close)

    # The OpenSSL PRNG is seeded with only the pid, and apps with frequently
    # dying workers can recycle pids
    OpenSSL::Random.seed(rand.to_s) if defined?(OpenSSL::Random)
    # we'll re-trap EXIT_SIGS later for graceful shutdown iff we accept clients
    EXIT_SIGS.each { |sig| trap(sig) { exit!(0) } }
    exit!(0) if (@sig_queue & EXIT_SIGS)[0] # did we inherit sigs from parent?
    @sig_queue = []

    # ignore WINCH, TTIN, TTOU, HUP in the workers
    (Yahns::Server::QUEUE_SIGS - EXIT_SIGS).each { |sig| trap(sig, nil) }
    trap(:CHLD, 'DEFAULT')
    @logger.info("worker=#{worker.nr} spawned pid=#$$")
    proc_name "worker[#{worker.nr}]"
    Yahns::START.clear
    @sev.close
    @sev = Yahns::Sigevent.new
    switch_user(*@user) if @user
    @user = @workers = nil
    __call_hooks(@atfork_child, worker.nr)
    @atfork_child = @atfork_parent = @atfork_prepare = nil
  end

  def __call_hooks(ary, worker_nr)
    ary.each { |x| x.call(worker_nr) } if ary
  end

  def spawn_missing_workers
    worker_nr = -1
    until (worker_nr += 1) == @worker_processes
      @workers.value?(worker_nr) and next
      worker = Yahns::Worker.new(worker_nr)
      @logger.info("worker=#{worker_nr} spawning...")
      __call_hooks(@atfork_prepare, worker_nr)
      if pid = fork
        @workers[pid] = worker.atfork_parent
        # XXX is this useful?
        __call_hooks(@atfork_parent, worker_nr)
      else
        worker_atfork_internal(worker)
        run_mp_worker(worker)
      end
    end
  rescue => e
    Yahns::Log.exception(@logger, "spawning worker", e)
    exit!
  end

  # monitors children and receives signals forever
  # (or until a termination signal is sent).  This handles signals
  # one-at-a-time time and we'll happily drop signals in case somebody
  # is signalling us too often.
  def join
    spawn_missing_workers
    state = :respawn # :QUIT, :WINCH
    proc_name 'master'
    @logger.info "master process ready"
    daemon_ready
    begin
      @sev.wait_readable
      @sev.yahns_step
      reap_all
      case @sig_queue.shift
      when *EXIT_SIGS # graceful shutdown (twice for non graceful)
        @listeners.each(&:close).clear
        soft_kill_each_worker("QUIT")
        state = :QUIT
      when :USR1 # rotate logs
        usr1_reopen("master ")
        soft_kill_each_worker("USR1")
      when :USR2 # exec binary, stay alive in case something went wrong
        reexec
      when :WINCH
        if $stdin.tty?
          @logger.info "SIGWINCH ignored because we're not daemonized"
        else
          state = :WINCH
          @logger.info "gracefully stopping all workers"
          soft_kill_each_worker("QUIT")
          @worker_processes = 0
        end
      when :TTIN
        state = :respawn unless state == :QUIT
        @worker_processes += 1
      when :TTOU
        @worker_processes -= 1 if @worker_processes > 0
      when :HUP
        state = :respawn unless state == :QUIT
        if @config.config_file
          load_config!
        else # exec binary and exit if there's no config file
          @logger.info "config_file not present, reexecuting binary"
          reexec
        end
      end while @sig_queue[0]
      maintain_worker_count if state == :respawn
    rescue => e
      Yahns::Log.exception(@logger, "master loop error", e)
    end while state != :QUIT || @workers.size > 0
    @logger.info "master complete"
    unlink_pid_safe(@pid) if @pid
  end

  def fdmap_init_mp
    fdmap = fdmap_init # builds apps (if not preloading)
    [:USR1, *EXIT_SIGS].each { |sig| trap(sig) { sqwakeup(sig) } }
    @config.postfork_cleanup # reduce live objects
    fdmap
  end

  def run_mp_worker(worker)
    fdmap = fdmap_init_mp
    alive = true
    watch = [ worker, @sev ]
    begin
      alive = mp_sig_handle(watch, alive)
    rescue => e
      Yahns::Log.exception(@logger, "main worker loop", e)
    end while alive || dropping(fdmap)
    exit
  ensure
    quit_finish
  end

  def mp_sig_handle(watch, alive)
    # not performance critical
    watch.delete_if { |io| io.to_io.closed? }
    tout = alive ? (@sig_queue.empty? ? nil : 0) : 0.01
    if r = select(watch, nil, nil, tout)
      r[0].each(&:yahns_step)
    end
    case @sig_queue.shift
    when *EXIT_SIGS
      return quit_enter(alive)
    when :USR1
      usr1_reopen("worker ")
    end
    alive
  end

  # reaps all unreaped workers/reexec processes
  def reap_all
    begin
      wpid, status = Process.waitpid2(-1, Process::WNOHANG)
      wpid or return
      if @reexec_pid == wpid
        @logger.error "reaped #{status.inspect} exec()-ed"
        @reexec_pid = 0
        self.pid = @pid.chomp('.oldbin') if @pid
        proc_name('master')
      else
        worker = @workers.delete(wpid)
        desc = worker ? "worker=#{worker.nr}" : "(unknown)"
        m = "reaped #{status.inspect} #{desc}"
        status.success? ? @logger.info(m) : @logger.error(m)
      end
    rescue Errno::ECHILD
      return
    end while true
  end
end
