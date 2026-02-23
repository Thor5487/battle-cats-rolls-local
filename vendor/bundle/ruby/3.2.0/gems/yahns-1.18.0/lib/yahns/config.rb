# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
#
# Implements a DSL for configuring a yahns server.
# See https://yhbt.net/yahns.git/tree/examples/yahns_multi.conf.rb
# for a full example configuration file.
class Yahns::Config # :nodoc:
  # public within yahns itself, NOT a public interface for users outside
  # of yahns.  See yahns/rack for usage example
  APP_CLASS = {}

  CfgBlock = Struct.new(:type, :ctx) # :nodoc:
  attr_reader :config_file, :config_listeners, :set
  attr_reader :qeggs, :app_ctx

  def initialize(config_file = nil)
    @config_file = config_file
    @block = nil
    config_reload!

    # FIXME: we shouldn't have this at all when we go Unicorn 5-only
    Unicorn::HttpParser.respond_to?(:keepalive_requests=) and
      Unicorn::HttpParser.keepalive_requests = 0xffffffff
  end

  def _check_in_block(ctx, var)
    if ctx.nil?
      return var if @block.nil?
      msg = "#{var} must be called outside of #{@block.type}"
    else
      ctx = Array(ctx)
      return var if @block && ctx.include?(@block.type)
      msg = @block ? "may not be used inside a #{@block.type} block" :
                     "must be used with a #{ctx.join(' or ')} block"
    end
    raise ArgumentError, msg
  end

  def postfork_cleanup
    @app_ctx = @set = @qeggs = @app_instances = @config_file = nil
  end

  def config_reload! #:nodoc:
    # app_instance:app_ctx is a 1:N relationship
    @config_listeners = {} # name/address -> options
    @app_ctx = []
    @set = Hash.new(:unset)
    @qeggs = Hash.new { |h,k| h[k] = Yahns::QueueEgg.new }
    @app_instances = {}

    # set defaults:
    client_expire_threshold(0.5) # default is half of the open file limit

    instance_eval(File.read(@config_file), @config_file) if @config_file

    # working_directory binds immediately (easier error checking that way),
    # now ensure any paths we changed are correctly set.
    [ :pid, :stderr_path, :stdout_path ].each do |var|
      String === (path = @set[var]) or next
      path = File.expand_path(path)
      File.writable?(path) || File.writable?(File.dirname(path)) or \
            raise ArgumentError, "directory for #{var}=#{path} not writable"
    end
  end

  def logger(obj)
    var = :logger
    %w(debug info warn error fatal).each do |m|
      obj.respond_to?(m) and next
      raise ArgumentError, "#{var}=#{obj} does not respond to method=#{m}"
    end
    if @block
      if @block.ctx.respond_to?(:logger=)
        @block.ctx.logger = obj
      else
        raise ArgumentError, "#{var} not valid inside #{@block.type}"
      end
    else
      @set[var] = obj
    end
  end

  def shutdown_timeout(sec)
    var = _check_in_block(nil, :shutdown_timeout)
    @set[var] = _check_num(var, sec, 0)
  end

  def worker_processes(nr, &blk)
    var =_check_in_block(nil, :worker_processes)
    @set[var] = _check_int(var, nr, 1)
    if block_given?
      @block = CfgBlock.new(var, nil)
      instance_eval(&blk)
      @block = nil
    end
  end

  %w(atfork_prepare atfork_parent atfork_child).each do |fn|
    eval(
    "def #{fn}(*args, &blk);" \
    "  _check_in_block([:worker_processes,:app], :#{fn});" \
    "  _add_hook(:#{fn}, block_given? ? blk : args[0]);" \
    'end'
    )
  end

  def before_exec(&blk)
    var = _check_in_block(nil, :before_exec)
    @set[var] = (block_given? ? blk : args[0])
  end

  def _add_hook(var, my_proc)
    Proc === my_proc or
      raise ArgumentError, "invalid type: #{var}=#{my_proc.inspect}"

    # this sets:
    # :atfork_prepare, :atfork_parent, :atfork_child
    key = var.to_sym
    @set[key] = [] unless @set.include?(key)
    @set[key] << my_proc
  end

  # sets the +path+ for the PID file of the yahns master process
  def pid(path)
    _set_path(:pid, path)
  end

  def stderr_path(path)
    _set_path(:stderr_path, path)
  end

  def stdout_path(path)
    _set_path(:stdout_path, path)
  end

  def value(var)
    val = @set[var]
    val == :unset ? nil : val
  end

  # sets the working directory for yahns.  This ensures SIGUSR2 will
  # start a new instance of yahns in this directory.  This may be
  # a symlink, a common scenario for Capistrano users.  Unlike
  # all other yahns configuration directives, this binds immediately
  # for error checking and cannot be undone by unsetting it in the
  # configuration file and reloading.
  def working_directory(path)
    var = _check_in_block(nil, :working_directory)
    @app_ctx.empty? or
      raise ArgumentError, "#{var} must be declared before any apps"

    # just let chdir raise errors
    path = File.expand_path(path)
    if @config_file &&
       @config_file[0] != ?/ &&
       ! File.readable?("#{path}/#@config_file")
      raise ArgumentError,
            "config_file=#@config_file would not be accessible in" \
            " #{var}=#{path}"
    end
    Dir.chdir(path)
    @set[var] = ENV["PWD"] = path
  end

  # Runs worker processes as the specified +user+ and +group+.
  # The master process always stays running as the user who started it.
  # This switch will occur after calling the after_fork hooks, and only
  # if the Worker#user method is not called in the after_fork hooks
  # +group+ is optional and will not change if unspecified.
  def user(user, group = nil)
    var = _check_in_block(nil, :user)
    @block and raise "#{var} is not valid inside #{@block.type}"
    # raises ArgumentError on invalid user/group
    Etc.getpwnam(user)
    Etc.getgrnam(group) if group
    @set[var] = [ user, group ]
  end

  def _set_path(var, path) #:nodoc:
    _check_in_block(nil, var)
    case path
    when NilClass, String
      @set[var] = path
    else
      raise ArgumentError
    end
  end

  def listen(address, options = {})
    options = options.dup
    var = _check_in_block(:app, :listen)
    address = expand_addr(address)
    String === address or
      raise ArgumentError, "address=#{address.inspect} must be a string"
    [ :umask, :backlog ].each do |key|
      # :backlog may be negative on some OSes
      value = options[key] or next
      Integer === value or
        raise ArgumentError, "#{var}: not an integer: #{key}=#{value.inspect}"
    end
    [ :sndbuf, :rcvbuf, :threads ].each do |key|
       value = options[key] and _check_int(key, value, 1)
    end

    [ :ipv6only, :reuseport ].each do |key|
      (value = options[key]).nil? and next
      [ true, false ].include?(value) or
        raise ArgumentError, "#{var}: not boolean: #{key}=#{value.inspect}"
    end

    require_relative('openssl_server') if options[:ssl_ctx]

    options[:yahns_app_ctx] = @block.ctx
    @config_listeners.include?(address) and
      raise ArgumentError, "listen #{address} already in use"
    @config_listeners[address] = options
  end

  # expands "unix:path/to/foo" to a socket relative to the current path
  # expands pathnames of sockets if relative to "~" or "~username"
  # expands "*:port and ":port" to "0.0.0.0:port"
  def expand_addr(address) #:nodoc:
    return "0.0.0.0:#{address}" if Integer === address
    return address unless String === address

    case address
    when %r{\Aunix:(.*)\z}
      File.expand_path($1)
    when %r{\A~}
      File.expand_path(address)
    when %r{\A(?:\*:)?(\d+)\z}
      "0.0.0.0:#$1"
    when %r{\A\[([a-fA-F0-9:]+)\]\z}, %r/\A((?:\d+\.){3}\d+)\z/
      canonicalize_tcp($1, 80)
    when %r{\A\[([a-fA-F0-9:]+)\]:(\d+)\z}, %r{\A(.*):(\d+)\z}
      canonicalize_tcp($1, $2.to_i)
    else
      address
    end
  end

  def canonicalize_tcp(addr, port)
    packed = Socket.pack_sockaddr_in(port, addr)
    port, addr = Socket.unpack_sockaddr_in(packed)
    addr.include?(':') ? "[#{addr}]:#{port}" : "#{addr}:#{port}"
  end

  def queue(*args, &block)
    var = :queue
    prev_block = @block
    if prev_block
      _check_in_block(:app, var)
      if block_given?
        args.size == 0 or
          raise ArgumentError,
                "queues defined with a block inside app must not have names"
        name = @block
      else
        name = args[0] or
          raise ArgumentError, "queue must be given a name if no block given"
      end
    else
      name = args[0] || :default
    end
    args.size > 1 and
      raise ArgumentError, "queue only takes one name argument"
    qegg = @qeggs[name]
    if block_given?
      @block = CfgBlock.new(:queue, qegg)
      instance_eval(&block)
      @block = prev_block
    end

    # associate the queue if we're inside an app
    prev_block.ctx.qegg = qegg if prev_block
  end

  # queue parameters (Yahns::QueueEgg)
  %w(max_events worker_threads).each do |_v|
    eval(
    "def #{_v}(val);" \
    "  _check_in_block(:queue, :#{_v});" \
    "  @block.ctx.__send__(%Q(#{_v}=), _check_int(:#{_v}, val, 1));" \
    'end'
    )
  end

  def _check_int(var, n, min)
    Integer === n or raise ArgumentError, "not an integer: #{var}=#{n.inspect}"
    n >= min or raise ArgumentError, "too low (< #{min}): #{var}=#{n.inspect}"
    n
  end

  def _check_num(var, n, min)
    Numeric === n or raise ArgumentError, "not a number: #{var}=#{n.inspect}"
    n >= min or raise ArgumentError, "too low (< #{min}): #{var}=#{n.inspect}"
    n
  end

  # global
  def client_expire_threshold(val)
    var = _check_in_block(nil, :client_expire_threshold)
    case val
    when Float
      (val > 0 && val <= 1.0) or
        raise ArgumentError, "#{var} must be > 0 and <= 1.0 if a ratio"
    when Integer
    else
      raise ArgumentError, "#{var} must be a float or integer"
    end
    @set[var] = val
  end

  # type = :rack
  def app(type, *args, &block)
    var = _check_in_block(nil, :app)
    file = "yahns/#{type.to_s}"
    begin
      require file
    rescue LoadError => e
      raise ArgumentError, "#{type.inspect} is not a supported app type",
            e.backtrace
    end
    klass = APP_CLASS[type] or
      raise TypeError,
        "#{var}: #{file} did not register #{type} in #{self.class}::APP_CLASS"

    # apps may have multiple configurator contexts
    app_cfg = @app_instances[klass.instance_key(*args)] = klass.new(*args)
    ctx = app_cfg.config_context
    if block_given?
      @block = CfgBlock.new(:app, ctx)
      instance_eval(&block)
      @block = nil
    end
    @app_ctx << ctx
  end

  def _check_bool(var, val)
    return val if [ true, false ].include?(val)
    raise ArgumentError, "#{var} must be boolean"
  end

  # boolean config directives for app
  %w(check_client_connection persistent_connections).each do |_v|
    eval(
    "def #{_v}(bool);" \
    "  _check_in_block(:app, :#{_v});" \
    "  @block.ctx.__send__(%Q(#{_v}=), _check_bool(:#{_v}, bool));" \
    'end'
    )
  end

  def output_buffering(bool, opts = {})
    var = _check_in_block(:app, :output_buffering)
    @block.ctx.__send__("#{var}=", _check_bool(var, bool))
    tmpdir = opts[:tmpdir] and
      @block.ctx.output_buffer_tmpdir = _check_tmpdir(var, tmpdir)
  end

  def _check_tmpdir(var, path)
    File.directory?(path) or
      raise ArgumentError, "#{var} tmpdir: #{path} is not a directory"
    File.writable?(path) or
      raise ArgumentError, "#{var} tmpdir: #{path} is not writable"
    path
  end

  # integer config directives for app
  {
    # config name, minimum value
    client_body_buffer_size: 1,
    client_header_buffer_size: 1,
  }.each do |_v,minval|
    eval(
    "def #{_v}(val);" \
    "  _check_in_block(:app, :#{_v});" \
    "  @block.ctx.__send__(%Q(#{_v}=), _check_int(:#{_v}, val, #{minval}));" \
    'end'
    )
  end

  def client_timeout(val)
    var = _check_in_block(:app, :client_timeout)
    @block.ctx.__send__("#{var}=", _check_num(var, val, 0))
  end

  def client_max_body_size(val)
    var = _check_in_block(:app, :client_max_body_size)
    val = _check_int(var, val, 0) if val != nil
    @block.ctx.__send__("#{var}=", val)
  end

  def input_buffering(val, opts = {})
    var = _check_in_block(:app, :input_buffering)
    ok = [ :lazy, true, false ]
    ok.include?(val) or
      raise ArgumentError, "`#{var}' must be one of: #{ok.inspect}"
    @block.ctx.__send__("#{var}=", val)
    tmpdir = opts[:tmpdir] and
      @block.ctx.input_buffer_tmpdir = _check_tmpdir(var, tmpdir)
  end

  # used to configure rack.errors destination
  def errors(val)
    var = _check_in_block(:app, :errors)
    if String === val
      # we've already bound working_directory by the time we get here
      val = File.open(File.expand_path(val), "ab")
      val.sync = true
    else
      rt = [ :puts, :write, :flush ] # match Rack::Lint
      rt.all? { |m| val.respond_to?(m) } or raise ArgumentError,
                   "`#{var}' destination must respond to all of: #{rt.inspect}"
    end
    @block.ctx.__send__("#{var}=", val)
  end

  def commit!(server)
    # redirect IOs
    { stdout_path: $stdout, stderr_path: $stderr }.each do |key, io|
      path = @set[key]
      if path == :unset && server.daemon_pipe
        @set[key] = path = "/dev/null"
      end
      File.open(path, 'a') { |fp| io.reopen(fp) } if String === path
      io.sync = true
    end

    [ :logger, :pid, :worker_processes, :user, :shutdown_timeout, :before_exec,
      :atfork_prepare, :atfork_parent, :atfork_child
    ].each do |var|
      val = @set[var]
      server.__send__("#{var}=", val) if val != :unset
    end

    @app_ctx.each { |app| app.logger ||= server.logger }
  end

  def register_inherited(name)
    return unless @config_listeners.empty? && @app_ctx.size == 1
    @config_listeners[name] = { :yahns_app_ctx => @app_ctx[0] }
  end
end
