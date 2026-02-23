# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'
require 'timeout'
require 'socket'
require 'net/http'

module ServerHelper
  def check_err(err = @err)
    err = File.open(err.path, "r") if err.respond_to?(:path)
    err.rewind
    lines = err.readlines
    bad_lines = lines.dup.delete_if { |l| l =~ /INFO/ }
    assert bad_lines.empty?, lines.join("\n")
    err.close! if err == @err
  end

  def poke_until_dead(pid)
    assert_operator pid, :>, 0
    Timeout.timeout(10) do
      begin
        Process.kill(0, pid)
        sleep(0.01)
      rescue Errno::ESRCH
        break
      end while true
    end
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
  end

  def quit_wait(pid)
    pid or return
    err = $! and warn "Terminating on #{err.inspect} (#{err.class})"
    Process.kill(:QUIT, pid)
    _, status = Timeout.timeout(10) { Process.waitpid2(pid) }
    assert status.success?, status.inspect
  rescue Timeout::Error => tout
    err ||= tout
    begin
      warn "#{err.message} (#{err.class})"
      err.backtrace.each { |l| warn l }
    end
    if RUBY_PLATFORM =~ /linux/
      system("lsof -p #{pid}")
      warn "#{pid} failed to die, waiting for user to inspect"
      sleep
    end
    raise
  end

  # only use for newly bound sockets
  def get_tcp_client(host, port, tries = 500)
    begin
      return TCPSocket.new(host, port)
    rescue Errno::ECONNREFUSED
      raise if tries < 0
      tries -= 1
    end while sleep(0.01)
  end

  def server_helper_teardown
    @srv.close if defined?(@srv) && !@srv.closed?
    @ru.close! if defined?(@ru) && @ru
    check_err if defined?(@err)
    Timeout.timeout(30) do
      Process.kill(:TERM, @tail_pid)
      Process.waitpid(@tail_pid)
    end if @tail_pid
  end

  def server_helper_setup
    @srv = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    @err = tmpfile(%w(srv .err))
    @ru = nil
    @tail_pid = nil
    case tail = ENV['TAIL']
    when '1'
      tail = 'tail -f' # POSIX
    when nil, '0'
      tail = nil
    # else : allow users to specify 'tail -F' or 'gtail -F' for GNU
    end
    if tail
      cmd = tail.split(/\s+/)
      cmd << @err.path
      @tail_pid = spawn(*cmd)
    end
  end

  def mkserver(cfg, srv = @srv)
    xfork do
      ENV["YAHNS_FD"] = srv.fileno.to_s
      srv.autoclose = false
      yield if block_given?
      Yahns::Server.new(cfg).start.join
    end
  end

  def wait_for_full(c)
    prev = 0
    prev_time = Time.now
    begin
      nr = c.nread
      break if nr > 0 && nr == prev && (Time.now - prev_time) > 0.5
      if nr != prev
        prev = nr
        prev_time = Time.now
      end
      Thread.pass
    end while sleep(0.1)
  end
end

module TrywriteBlocked
  def kgio_trywrite(*args)
    return :wait_writable if $_tw_block_on.include?($_tw_blocked += 1)
    super
  end

  def kgio_syssend(*args)
    return :wait_writable if $_tw_block_on.include?($_tw_blocked += 1)
    super
  end
end
