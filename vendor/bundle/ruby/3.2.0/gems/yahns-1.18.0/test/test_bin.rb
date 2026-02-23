# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
class TestBin < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias teardown server_helper_teardown

  def setup
    server_helper_setup
    @cmd = %W(#{RbConfig.ruby} -I lib bin/yahns)
  end

  def test_listen_fd3
    return unless RUBY_VERSION.to_f > 2.3 # Fixed in ruby/trunk r51209, actually
    host, port = @srv.addr[3], @srv.addr[1]

    ru = tmpfile(%w(test_bin_daemon .ru))
    ru.write("require 'rack/lobster'; run Rack::Lobster.new\n")
    cmd = %W(#{RbConfig.ruby} -I lib bin/yahns-rackup -E none #{ru.path})
    [ %w(-O listen=inherit), %W(-p #{port} -o #{host}) ].each do |opt|
      @srv.setsockopt(:SOL_SOCKET, :SO_KEEPALIVE, 0)
      begin
        pid = xfork do # emulate a systemd environment
          env = { 'LISTEN_PID' => $$.to_s, 'LISTEN_FDS' => '1' }
          cmd.concat(opt)
          exec env, *cmd, 3 => @srv, err: @err.path
        end
        Net::HTTP.start(host, port) do |http|
          req = Net::HTTP::Get.new("/")
          res = http.request(req)
          assert_equal 200, res.code.to_i
          assert_equal "keep-alive", res["Connection"]
        end
        assert @srv.getsockopt(:SOL_SOCKET, :SO_KEEPALIVE).bool,
                     'ensure the inheriting process applies TCP socket options'
      ensure
        if pid
          Process.kill(:QUIT, pid)
          _, status = Process.waitpid2(pid)
          assert status.success?, status.inspect
        end
      end
    end
  ensure
    ru.close! if ru
  end

  def test_bin_daemon_noworker_inherit
    bin_daemon(false, true)
  end

  def test_bin_daemon_worker_inherit
    bin_daemon(true, true)
  end

  def test_bin_daemon_noworker_bind
    bin_daemon(false, false)
  end

  def test_bin_daemon_worker_bind
    bin_daemon(true, false)
  end

  def bin_daemon(worker, inherit)
    @srv.close unless inherit
    @pid = tmpfile(%w(test_bin_daemon .pid))
    @ru = tmpfile(%w(test_bin_daemon .ru))
    @ru.write("require 'rack/lobster'; run Rack::Lobster.new\n")
    cfg = tmpfile(%w(test_bin_daemon_conf .rb))
    cfg.puts "pid '#{@pid.path}'"
    cfg.puts "stderr_path '#{@err.path}'"
    cfg.puts "worker_processes 1" if worker
    cfg.puts "app(:rack, '#{@ru.path}', preload: false) do"
    cfg.puts "  listen ENV['YAHNS_TEST_LISTEN']"
    cfg.puts "end"
    @cmd.concat(%W(-D -c #{cfg.path}))
    addr = cloexec_pipe
    pid = xfork do
      opts = { close_others: true }
      addr[0].close
      if inherit
        opts[@srv.fileno] = @srv
        ENV["YAHNS_FD"] = @srv.fileno.to_s
      else
        # we must create the socket inside the child and tell the parent
        # about it to avoid sharing
        @srv = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
      end
      @cmd << opts
      host, port = @srv.addr[3], @srv.addr[1]
      listen = ENV["YAHNS_TEST_LISTEN"] = "#{host}:#{port}"
      addr[1].write(listen)
      addr[1].close

      # close/FD_CLOEXEC may be insufficient since the socket could be
      # released asynchronously, leading to occasional test failures.
      # Even with a synchronous FD_CLOEXEC, there's a chance of a race
      # because the server does not bind right away.
      unless inherit
        begin
          @srv.shutdown
        rescue Errno::ENOTCONN
        end
        @srv.close
      end
      exec(*@cmd)
    end
    addr[1].close
    listen = Timeout.timeout(10) { addr[0].read }
    addr[0].close
    host, port = listen.split(/:/, 2)
    port = port.to_i
    assert_operator port, :>, 0

    unless inherit
      # daemon_pipe guarantees socket will be usable after this:
      Timeout.timeout(10) do # Ruby startup is slow!
        _, status = Process.waitpid2(pid)
        assert status.success?, status.inspect
      end
    end

    Net::HTTP.start(host, port) do |http|
      req = Net::HTTP::Get.new("/")
      res = http.request(req)
      assert_equal 200, res.code.to_i
      assert_equal "keep-alive", res["Connection"]
    end
  rescue => e
    warn "#{e.message} (#{e.class})"
    e.backtrace.each { |l| warn "#{l}" }
    raise
  ensure
    cfg.close! if cfg
    pid = File.read(@pid.path)
    pid = pid.to_i
    assert_operator pid, :>, 0
    Process.kill(:QUIT, pid)
    if inherit
      _, status = Timeout.timeout(10) { Process.waitpid2(pid) }
      assert status.success?, status.inspect
    else
      poke_until_dead pid
    end
    @pid.close! if @pid
  end

  def test_usr2_preload_noworker; usr2(true, false); end
  def test_usr2_preload_worker; usr2(true, true); end
  def test_usr2_nopreload_worker; usr2(false, true); end
  def test_usr2_nopreload_noworker; usr2(false, false); end

  def usr2(preload, worker)
    yahns_mktmpdir { |tmpdir| usr2_dir(tmpdir, preload, worker) }
  end

  def usr2_dir(tmpdir, preload, worker)
    exe = "#{tmpdir}/yahns"

    # need to fork here since tests are MT and the FD can leak out and go to
    # other processes which fork (but do not exec), causing ETXTBUSY on
    # Process.spawn
    pid = xfork do
      File.open(exe, "w") { |y|
        lines = File.readlines("bin/yahns")
        lines[0] = "#!#{RbConfig.ruby}\n"
        y.chmod(0755)
        y.syswrite(lines.join)
      }
    end
    _, status = Process.waitpid2(pid)
    assert status.success?, status.inspect

    @pid = tmpfile(%w(test_bin_daemon .pid))
    host, port = @srv.addr[3], @srv.addr[1]
    @ru = tmpfile(%w(test_bin_daemon .ru))
    @ru.puts("use Rack::ContentLength")
    @ru.puts("use Rack::ContentType, 'text/plain'")
    @ru.puts("run lambda { |_| [ 200, {}, [ Process.pid.to_s ] ] }")
    cfg = tmpfile(%w(test_bin_daemon_conf .rb))
    cfg.puts "pid '#{@pid.path}'"
    cfg.puts "stderr_path '#{@err.path}'"
    cfg.puts "worker_processes 1" if worker
    cfg.puts "app(:rack, '#{@ru.path}', preload: #{preload}) do"
    cfg.puts "  listen '#{host}:#{port}'"
    cfg.puts "end"
    env = {
      "YAHNS_FD" => @srv.fileno.to_s,
      "PATH" => "#{tmpdir}:#{ENV['PATH']}",
      "RUBYLIB" => "#{Dir.pwd}/lib",
    }
    cmd = %W(#{exe} -D -c #{cfg.path})
    cmd << { @srv => @srv, close_others: true }
    pid = Process.spawn(env, *cmd)
    res = Net::HTTP.start(host, port) { |h| h.get("/") }
    assert_equal 200, res.code.to_i
    orig = res.body
    Process.kill(:USR2, pid)
    newpid = pid
    Timeout.timeout(10) do
      begin
        newpid = File.read(@pid.path)
      rescue Errno::ENOENT
      end while newpid.to_i == pid && sleep(0.01)
    end
    Process.kill(:QUIT, pid)
    _, status = Timeout.timeout(10) { Process.waitpid2(pid) }
    assert status.success?, status
    res = Net::HTTP.start(host, port) { |h| h.get("/") }
    assert_equal 200, res.code.to_i
    second = res.body
    refute_equal orig, second

    newpid = newpid.to_i
    assert_operator newpid, :>, 0
    Process.kill(:HUP, newpid)
    third = second
    Timeout.timeout(10) do
      begin
        third = Net::HTTP.start(host, port) { |h| h.get("/") }.body
      end while third == second && sleep(0.01)
    end
    if worker
      Process.kill(0, newpid) # nothing should raise
    else
      poke_until_dead newpid
    end
  ensure
    File.unlink(exe) if exe
    cfg.close! if cfg
    pid = File.read(@pid.path)
    pid = pid.to_i
    assert_operator pid, :>, 0
    Process.kill(:QUIT, pid)
    poke_until_dead pid
    @pid.close!
  end
end
