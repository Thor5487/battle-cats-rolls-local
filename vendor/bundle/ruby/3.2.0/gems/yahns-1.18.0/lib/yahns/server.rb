# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'queue_quitter'
require_relative 'tcp_server'
require_relative 'unix_server'

class Yahns::Server # :nodoc:
  QUEUE_SIGS = [ :WINCH, :QUIT, :INT, :TERM, :USR1, :USR2, :HUP, :TTIN, :TTOU,
                 :CHLD ]
  attr_accessor :daemon_pipe
  attr_accessor :logger
  attr_writer :user
  attr_writer :before_exec
  attr_writer :worker_processes
  attr_writer :shutdown_timeout
  attr_writer :atfork_prepare
  attr_writer :atfork_parent
  attr_writer :atfork_child
  include Yahns::SocketHelper

  def initialize(config)
    @shutdown_expire = nil
    @shutdown_timeout = nil
    @reexec_pid = 0
    @daemon_pipe = nil # writable IO or true
    @config = config
    @workers = {} # pid -> workers
    @sig_queue = [] # nil in forked workers
    @logger = Logger.new($stderr)
    @sev = Yahns::Sigevent.new
    @listeners = []
    @pid = nil
    @worker_processes = nil
    @before_exec = nil
    @atfork_prepare = @atfork_parent = @atfork_child = nil
    @user = nil
    @queues = []
    @wthr = []
  end

  def sqwakeup(sig)
    @sig_queue << sig
    @sev.sev_signal
  end

  def start
    @config.commit!(self)
    inherit_listeners!
    # we try inheriting listeners first, so we bind them later.
    # we don't write the pid file until we've bound listeners in case
    # yahns was started twice by mistake.

    # setup signal handlers before writing pid file in case people get
    # trigger happy and send signals as soon as the pid file exists.
    QUEUE_SIGS.each { |sig| trap(sig) { sqwakeup(sig) } }
    bind_new_listeners!
    self.pid = @config.value(:pid) # write pid file
    if @worker_processes
      require_relative 'server_mp'
      extend Yahns::ServerMP
    else
      switch_user(*@user) if @user
    end
    self
  end

  def switch_user(user, group = nil)
    # we do not protect the caller, checking Process.euid == 0 is
    # insufficient because modern systems have fine-grained
    # capabilities.  Let the caller handle any and all errors.
    uid = Etc.getpwnam(user).uid
    gid = Etc.getgrnam(group).gid if group
    Yahns::Log.chown_all(uid, gid)
    if gid && Process.egid != gid
      Process.initgroups(user, gid)
      Process::GID.change_privilege(gid)
    end
    Process.euid != uid and Process::UID.change_privilege(uid)
  end

  def drop_acceptors
    @listeners.delete_if(&:ac_quit)
  end

  # replaces current listener set with +listeners+.  This will
  # close the socket if it will not exist in the new listener set
  def listeners=(listeners)
    cur_names, dead_names = [], []
    listener_names.each do |name|
      if ?/ == name[0]
        # mark unlinked sockets as dead so we can rebind them
        (File.socket?(name) ? cur_names : dead_names) << name
      else
        cur_names << name
      end
    end
    set_names = listener_names(listeners)
    dead_names.concat(cur_names - set_names).uniq!
    dying = []
    @listeners.delete_if do |io|
      if dead_names.include?(sock_name(io))
        if io.ac_quit
          true
        else
          dying << io
          false
        end
      else
        set_server_sockopt(io, sock_opts(io))
        false
      end
    end

    dying.delete_if(&:ac_quit) while dying[0]

    (set_names - cur_names).each { |addr| listen(addr) }
  end

  def clobber_pid(path)
    unlink_pid_safe(@pid) if @pid
    if path
      fp = begin
        tmp = "#{File.dirname(path)}/#{rand}.#$$"
        File.open(tmp, File::RDWR|File::CREAT|File::EXCL, 0644)
      rescue Errno::EEXIST
        retry
      end
      fp.syswrite("#$$\n")
      File.rename(fp.path, path)
      fp.close
    end
  end

  # sets the path for the PID file of the master process
  def pid=(path)
    if path
      if x = valid_pid?(path)
        return path if @pid && path == @pid && x == $$
        if x == @reexec_pid && @pid =~ /\.oldbin\z/
          @logger.warn("will not set pid=#{path} while reexec-ed "\
                       "child is running PID:#{x}")
          return
        end
        raise ArgumentError, "Already running on PID:#{x} " \
                             "(or pid=#{path} is stale)"
      end
    end

    # rename the old pid if possible
    if @pid && path
      begin
        File.rename(@pid, path)
      rescue Errno::ENOENT, Errno::EXDEV
        # a user may have accidentally removed the original,
        # obviously cross-FS renames don't work, either.
        clobber_pid(path)
      end
    else
      clobber_pid(path)
    end
    @pid = path
  end

  # add a given address to the +listeners+ set, idempotently
  # Allows workers to add a private, per-process listener via the
  # after_fork hook.  Very useful for debugging and testing.
  # +:tries+ may be specified as an option for the number of times
  # to retry, and +:delay+ may be specified as the time in seconds
  # to delay between retries.
  # A negative value for +:tries+ indicates the listen will be
  # retried indefinitely, this is useful when workers belonging to
  # different masters are spawned during a transparent upgrade.
  def listen(address)
    address = @config.expand_addr(address)
    return if String === address && listener_names.include?(address)
    delay = 0.5
    tries = 5

    begin
      opts = sock_opts(address)
      io = bind_listen(address, opts)
      io = server_cast(io, opts) unless io.class.name.start_with?('Yahns::')
      @logger.info "listening on addr=#{sock_name(io)} fd=#{io.fileno}"
      @listeners << io
      io
    rescue Errno::EADDRINUSE => err
      if tries == 0
        @logger.error "adding listener failed addr=#{address} (in use)"
        raise err
      end
      tries -= 1
      @logger.warn "retrying in #{delay} seconds " \
                   "(#{tries < 0 ? 'infinite' : tries} tries left)"
      sleep(delay)
      retry
    rescue => err
      @logger.fatal "error adding listener addr=#{address}"
      raise err
    end
  end

  def daemon_ready
    @daemon_pipe.respond_to?(:syswrite) or return
    begin
      @daemon_pipe.syswrite("#$$")
    rescue => e
      @logger.warn("grandparent died too soon?: #{e.message} (#{e.class})")
    end
    @daemon_pipe.close
    @daemon_pipe = true # for SIGWINCH
  end

  # reexecutes the Yahns::START with a new binary
  def reexec
    if @reexec_pid > 0
      begin
        Process.kill(0, @reexec_pid)
        @logger.error "reexec-ed child already running PID:#@reexec_pid"
        return
      rescue Errno::ESRCH
        @reexec_pid = 0
      end
    end

    if @pid
      old_pid = "#@pid.oldbin"
      begin
        self.pid = old_pid  # clear the path for a new pid file
      rescue ArgumentError
        @logger.error "old PID:#{valid_pid?(old_pid)} running with " \
                      "existing pid=#{old_pid}, refusing rexec"
        return
      rescue => e
        @logger.error "error writing pid=#{old_pid} #{e.class} #{e.message}"
        return
      end
    end

    opt = {}
    @listeners.each { |sock| opt[sock.fileno] = sock }
    env = ENV.to_hash
    env['YAHNS_FD'] = opt.keys.join(',')
    opt[:close_others] = true
    cmd = [ Yahns::START[0] ].concat(Yahns::START[:argv])
    dir = @config.value(:working_directory) || Yahns::START[:cwd]
    @logger.info "spawning #{cmd.inspect} (in #{dir})"
    @reexec_pid = if @before_exec
      fork do
        Dir.chdir(dir)
        @before_exec.call(cmd)
        exec(env, *cmd, opt)
      end
    else
      opt[:chdir] = dir
      spawn(env, *cmd, opt)
    end
  end

  # unlinks a PID file at given +path+ if it contains the current PID
  # still potentially racy without locking the directory (which is
  # non-portable and may interact badly with other programs), but the
  # window for hitting the race condition is small
  def unlink_pid_safe(path)
    (File.read(path).to_i == $$ and File.unlink(path)) rescue nil
  end

  # returns a PID if a given path contains a non-stale PID file,
  # nil otherwise.
  def valid_pid?(path)
    wpid = File.read(path).to_i
    wpid <= 0 and return
    Process.kill(0, wpid)
    wpid
  rescue Errno::EPERM
    @logger.info "pid=#{path} possibly stale, got EPERM signalling PID:#{wpid}"
    nil
  rescue Errno::ESRCH, Errno::ENOENT
    # don't unlink stale pid files, racy without non-portable locking...
  end

  def load_config!
    @logger.info "reloading config_file=#{@config.config_file}"
    @config.config_reload!
    @config.commit!(self)
    soft_kill_each_worker("QUIT")
    Yahns::Log.reopen_all
    @logger.info "done reloading config_file=#{@config.config_file}"
  rescue StandardError, LoadError, SyntaxError => e
    Yahns::Log.exception(@logger,
                     "error reloading config_file=#{@config.config_file}", e)
  end

  # returns an array of string names for the given listener array
  def listener_names(listeners = @listeners)
    listeners.map { |io| sock_name(io) }
  end

  def sock_opts(io)
    @config.config_listeners[sock_name(io)] || {}
  end

  def inherit_listeners!
    # inherit sockets from parents, they need to be plain Socket objects
    # before they become Yahns::UNIXServer or Yahns::TCPServer
    #
    # Note: we intentionally use a yahns-specific environment variable
    # here because existing servers may use non-blocking listen sockets.
    # yahns uses _blocking_ listen sockets exclusively.  We cannot
    # change an existing socket to blocking mode if two servers are
    # running (one expecting blocking, one expecting non-blocking)
    # because that can completely break the non-blocking one.
    # Unfortunately, there is no one-off MSG_DONTWAIT-like flag for
    # accept4(2).
    inherited = ENV['YAHNS_FD'].to_s.split(',')

    # emulate sd_listen_fds() for systemd
    sd_pid, sd_fds = ENV.values_at('LISTEN_PID', 'LISTEN_FDS')
    if sd_pid.to_i == $$
      # 3 = SD_LISTEN_FDS_START
      inherited.concat((3...(3 + sd_fds.to_i)).to_a)
    end
    # to ease debugging, we will not unset LISTEN_PID and LISTEN_FDS

    inherited.map! do |fd|
      io = Socket.for_fd(fd.to_i)
      opts = sock_opts(io)
      io = server_cast(io, opts)
      set_server_sockopt(io, opts)
      name = sock_name(io)
      @logger.info "inherited addr=#{name} fd=#{io.fileno}"
      @config.register_inherited(name)
      io
    end

    @listeners.replace(inherited)
  end

  # call only after calling inherit_listeners!
  # This binds any listeners we did NOT inherit from the parent
  def bind_new_listeners!
    self.listeners = @config.config_listeners.keys
    raise ArgumentError, "no listeners" if @listeners.empty?
  end

  def proc_name(tag)
    s = Yahns::START
    $0 = ([ File.basename(s[0]), tag ]).concat(s[:argv]).join(' ')
  end

  def qegg_vivify(qegg, fdmap)
    queue = qegg.vivify(fdmap)
    qegg.worker_threads.times do
      @wthr << queue.worker_thread(@logger, qegg.max_events)
    end
    @queues << queue
    queue
  end

  # spins up processing threads of the server
  def fdmap_init
    thresh = @config.value(:client_expire_threshold)

    # keeps track of all connections, like ObjectSpace, but only for IOs
    fdmap = Yahns::Fdmap.new(@logger, thresh)

    # once initialize queues (epoll/kqueue) and associated worker threads
    queues = {}

    # spin up applications (which are preload: false)
    @config.app_ctx.each(&:after_fork_init)

    @shutdown_timeout ||= @config.app_ctx.map(&:client_timeout).max

    # spin up acceptor threads, clients flow into worker queues after this
    @listeners.each do |l|
      opts = sock_opts(l)
      ctx = opts[:yahns_app_ctx]
      ctx_list = opts[:yahns_app_ctx_list] ||= []
      qegg = ctx.qegg || @config.qeggs[:default]
      ctx.queue = queues[qegg] ||= qegg_vivify(qegg, fdmap)
      ctx = ctx.dup
      ctx.__send__(:include, l.expire_mod)
      if ssl_ctx = opts[:ssl_ctx]
        ctx.__send__(:include, Yahns::OpenSSLClient)
        env = ctx.app_defaults = ctx.app_defaults.dup
        env['HTTPS'] = 'on' # undocumented, but Rack::Request uses this
        env['rack.url_scheme'] = 'https'

        # avoid "session id context uninitialized" errors when a client
        # attempts to reuse a cached SSL session.  Server admins may
        # configure their own cache and session_id_context if desired.
        # 32 bytes is SSL_MAX_SSL_SESSION_ID_LENGTH and has been since
        # the SSLeay days
        ssl_ctx.session_id_context ||= OpenSSL::Random.random_bytes(32)

        # call OpenSSL::SSL::SSLContext#setup explicitly here to detect
        # errors and avoid race conditions.  We avoid calling this in the
        # parent process (if we have multiple workers) in case the
        # setup code starts TCP connections to memcached or similar
        # for session caching.
        ssl_ctx.setup
      end
      ctx_list << ctx
      # acceptors feed the the queues
      l.spawn_acceptor(opts[:threads] || 1, @logger, ctx)
    end
    fdmap
  end

  def usr1_reopen(prefix)
    @logger.info "#{prefix}reopening logs..."
    Yahns::Log.reopen_all
    @logger.info "#{prefix}done reopening logs"
  end

  def quit_enter(alive)
    if alive
      @logger.info("gracefully exiting shutdown_timeout=#@shutdown_timeout")
      @shutdown_expire ||= Yahns.now + @shutdown_timeout + 1
    else # drop connections immediately if signaled twice
      @logger.info("graceful exit aborted, exiting immediately")
      # we will still call any app-defined at_exit hooks here
      # use SIGKILL if you don't want that.
      exit
    end

    drop_acceptors # stop acceptors, we close epolls in quit_done
    @config.config_listeners.each_value do |opts|
      list= opts[:yahns_app_ctx_list] or next
      # Yahns::HttpContext#persistent_connections=
      list.each { |ctx| ctx.persistent_connections = false }
    end
    false
  end

  # drops all the the IO objects we have threads waiting on before exiting
  # This just injects the QueueQuitter object which acts like a
  # monkey wrench thrown into a perfectly good engine :)
  def quit_finish
    # we must not let quitters get GC-ed if we have any worker threads leftover
    @quitter = Yahns::QueueQuitter.new

    # throw the monkey wrench into the worker threads
    @queues.each { |q| q.queue_add(@quitter, Yahns::Queue::QEV_QUIT) }

    # watch the monkey wrench destroy all the threads!
    # Ugh, this may fail if we have dedicated threads trickling
    # response bodies out (e.g. "tail -F")  Oh well, have a timeout
    begin
      @wthr.delete_if { |t| t.join(0.01) }
      # Workaround Linux 5.5+ bug (fixed in 5.13+)
      # https://yhbt.net/lore/lkml/20210405231025.33829-1-dave@stgolabs.net/
      @wthr[0] && @queues[0].respond_to?(:queue_del) and @queues.each do |q|
        q.queue_del(@quitter)
        q.queue_add(@quitter, Yahns::Queue::QEV_QUIT)
      end
    end while @wthr[0] && Yahns.now <= @shutdown_expire

    # cleanup, our job is done
    @queues.each(&:close).clear
    @quitter.close # keep object around in case @wthr isn't empty
  rescue => e
    Yahns::Log.exception(@logger, "quit finish", e)
  ensure
    if (@wthr.size + @listeners.size) > 0
      @logger.warn("still active wthr=#{@wthr.size} "\
                   "listeners=#{@listeners.size}")
    end
  end

  def reap_reexec
    @reexec_pid > 0 or return
    wpid, status = Process.waitpid2(@reexec_pid, Process::WNOHANG)
    wpid or return
    @logger.error "reaped #{status.inspect} exec()-ed"
    @reexec_pid = 0
    self.pid = @pid.chomp('.oldbin') if @pid
  end

  def sp_sig_handle(alive)
    tout = alive ? (@sig_queue.empty? ? nil : 0) : 0.01
    @sev.wait_readable(tout)
    @sev.yahns_step
    case sig = @sig_queue.shift
    when :QUIT, :TERM, :INT
      return quit_enter(alive)
    when :CHLD
      reap_reexec
    when :USR1
      usr1_reopen(nil)
    when :USR2
      reexec
    when :HUP
      reexec
      return quit_enter(alive)
    when :TTIN, :TTOU, :WINCH
      @logger.info("SIG#{sig} ignored in single-process mode")
    end
    alive
  end

  def dropping(fdmap)
    if drop_acceptors[0] || fdmap.size > 0
      timeout = @shutdown_expire < Yahns.now ? -1 : @shutdown_timeout
      n = fdmap.desperate_expire(timeout)
      return false if n == 0 && @listeners.empty? # all done!

      # FIXME: sometimes shutdowns take a long time when using proxy_pass
      # Still not sure what's going on and it takes a while to reproduce..
      if timeout == -1
        @logger.error(
"exiting on shutdown_timeout=#@shutdown_timeout #{fdmap.size} FD(s) remain"
        )

        system('lsof', '-n', '-p', "#$$") if RUBY_PLATFORM =~ /linux/
        return false
      end

      $0 = "yahns quitting, #{n} FD(s) remain"
      true
    else
      false
    end
  end

  # single-threaded only, this is overriden if @worker_processes is non-nil
  def join
    daemon_ready
    fdmap = fdmap_init
    alive = true
    begin
      alive = sp_sig_handle(alive)
    rescue => e
      Yahns::Log.exception(@logger, "main loop", e)
    end while alive || dropping(fdmap)
    unlink_pid_safe(@pid) if @pid
  ensure
    quit_finish
  end
end
