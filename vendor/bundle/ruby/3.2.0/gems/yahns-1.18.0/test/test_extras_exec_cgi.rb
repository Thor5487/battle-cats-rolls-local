# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

# note: we use worker_processes to avoid polling/excessive wakeup issues
# in the test.  We recommend using worker_processes if using ExecCgi
class TestExtrasExecCGI < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown
  RUNME = "#{Dir.pwd}/test/test_extras_exec_cgi.sh"

  def test_exec_cgi
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    assert File.executable?(RUNME), "run test in project root"
    pid = mkserver(cfg) do
      require './extras/exec_cgi'
      cfg.instance_eval do
        stack = Rack::ContentLength.new(Rack::Chunked.new(ExecCgi.new(RUNME)))
        app(:rack, stack) { listen "#{host}:#{port}" }
        stderr_path err.path
        worker_processes 1
      end
    end

    Timeout.timeout(30) do # we can chunk
      c = get_tcp_client(host, port)
      c.write "GET / HTTP/1.1\r\nConnection: close\r\n" \
              "Host: example.com\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/, 2)
      assert_match %r{^Transfer-Encoding: chunked\b}, head
      assert_equal "5\r\nHIHI\n\r\n0\r\n\r\n", body
      c.close
      cerr = tmpfile(%w(curl .err))
      assert_equal "HIHI\n", `curl -sSfv 2>#{cerr.path} http://#{host}:#{port}/`
      assert_match %r{\bTransfer-Encoding: chunked\b}, cerr.read
      cerr.close!
    end

    Timeout.timeout(30) do # do not chunk on clients who can't handle chunking
      c = get_tcp_client(host, port)
      c.write "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/)
      assert_equal "HIHI\n", body
      refute_match %r{^Transfer-Encoding: chunked\b}, head
      c.close
    end

    Timeout.timeout(30) do # sure env is sane
      c = get_tcp_client(host, port)
      c.write "GET /env\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/)
      assert_nil body
      assert_match %r{^REQUEST_METHOD=GET$}, head
      assert_match %r{^PATH_INFO=/env$}, head
      assert_match %r{^QUERY_STRING=$}, head
      c.close
    end

    Timeout.timeout(30) do # known length should not chunk
      c = get_tcp_client(host, port)
      c.write "GET /known-length HTTP/1.1\r\nConnection: close\r\n" \
              "Host: example.com\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/, 2)
      refute_match %r{^Transfer-Encoding: chunked\b}, head
      assert_match %r{^Content-Length: 5\b}, head
      assert_equal "HIHI\n", body
      c.close
    end

    Timeout.timeout(30) do # 404
      c = get_tcp_client(host, port)
      c.write "GET /not-found HTTP/1.0\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/)
      assert_match %r{\AHTTP/1\.1 404 Not Found}, head
      assert_nil body
      c.close
    end

    Timeout.timeout(30) do # pid of executable
      c = get_tcp_client(host, port)
      c.write "GET /pid HTTP/1.0\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/, 2)
      assert_match %r{200 OK}, head
      assert_match %r{\A\d+\n\z}, body
      exec_pid = body.to_i
      c.close
      poke_until_dead exec_pid
    end
  ensure
    quit_wait(pid)
  end

  def test_cgi_died
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      require './extras/exec_cgi'
      cfg.instance_eval do
        stack = Rack::ContentLength.new(Rack::Chunked.new(ExecCgi.new(RUNME)))
        app(:rack, stack) { listen "#{host}:#{port}" }
        stderr_path err.path
        worker_processes 1
      end
    end
    exec_pid_tmp = tmpfile(%w(exec_cgi .pid))
    c = get_tcp_client(host, port)
    Timeout.timeout(20) do
      c.write "GET /die HTTP/1.0\r\nX-PID-DEST: #{exec_pid_tmp.path}\r\n\r\n"
      head, body = c.read.split(/\r\n\r\n/, 2)
      assert_match %r{500 Internal Server Error}, head
      assert_match "", body
      exec_pid = exec_pid_tmp.read
      assert_match %r{\A(\d+)\n\z}, exec_pid
      poke_until_dead exec_pid.to_i
    end
  ensure
    exec_pid_tmp.close! if exec_pid_tmp
    quit_wait(pid)
  end

  [ 9, 10, 11 ].each do |rtype|
    [ 1, 2, 3 ].each do |block_on|
      define_method("test_block_on_block_on_#{block_on}_rtype_#{rtype}") do
        _blocked_zombie([block_on], rtype)
      end
    end
  end

  def _blocked_zombie(block_on, rtype)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      $_tw_blocked = 0
      $_tw_block_on = block_on
      Yahns::HttpClient.__send__(:include, TrywriteBlocked)
      require './extras/exec_cgi'
      cfg.instance_eval do
        stack = Rack::ContentLength.new(Rack::Chunked.new(ExecCgi.new(RUNME)))
        app(:rack, stack) { listen "#{host}:#{port}" }
        stderr_path err.path
        worker_processes 1
      end
    end

    c = get_tcp_client(host, port)
    Timeout.timeout(20) do
      case rtype
      when 9 # non-persistent (HTTP/0.9)
        c.write "GET /pid\r\n\r\n"
        body = c.read
        assert_match %r{\A\d+\n\z}, body
        exec_pid = body.to_i
        poke_until_dead exec_pid
      when 10 # non-persistent (HTTP/1.0)
        c.write "GET /pid HTTP/1.0\r\n\r\n"
        head, body = c.read.split(/\r\n\r\n/, 2)
        assert_match %r{200 OK}, head
        assert_match %r{\A\d+\n\z}, body
        exec_pid = body.to_i
        poke_until_dead exec_pid
      when 11 # pid of executable, persistent
        c.write "GET /pid HTTP/1.0\r\nConnection: keep-alive\r\n\r\n"
        buf = ''.dup
        begin
          buf << c.readpartial(666)
        end until buf =~ /\r\n\r\n\d+\n/
        head, body = buf.split(/\r\n\r\n/, 2)
        assert_match %r{200 OK}, head
        assert_match %r{\A\d+\n\z}, body
        exec_pid = body.to_i
        poke_until_dead exec_pid
        assert_raises(EOFError) { c.readpartial(666) }
      else
        raise "BUG in test, bad rtype"
      end
    end
  ensure
    c.close if c
    quit_wait(pid)
  end

  def test_rlimit_options
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    tout = 1
    opts = { rlimit_cpu: tout, rlimit_core: 0 }
    cmd = [ '/bin/sh', '-c', 'while :; do :;done', opts ]
    pid = mkserver(cfg) do
      require './extras/exec_cgi'
      cfg.instance_eval do
        stack = Rack::ContentLength.new(Rack::Chunked.new(ExecCgi.new(*cmd)))
        app(:rack, stack) { listen "#{host}:#{port}" }
        stderr_path err.path
        worker_processes 1
      end
    end
    c = get_tcp_client(host, port)
    c.write "GET / HTTP/1.0\r\n\r\n"
    assert_same c, c.wait(tout + 5)
    assert_match %r{ 500 Internal Server Error\b}, c.readpartial(4096)
    c.close
  ensure
    quit_wait(pid)
  end
end
