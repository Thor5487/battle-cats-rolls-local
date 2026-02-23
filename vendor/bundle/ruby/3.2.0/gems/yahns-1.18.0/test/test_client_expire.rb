# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestClientExpire < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_client_expire_negative
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        ru = lambda { |e| h = { "Content-Length" => "0" }; [ 200, h, [] ] }
        app(:rack, ru) do
          listen "#{host}:#{port}", sndbuf: 2048, rcvbuf: 2048
        end
        client_expire_threshold(-10)
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) { |h|
      res = h.get("/")
      assert_empty res.body
    }
  ensure
    quit_wait(pid)
  end

  def test_client_expire
    require_exec "ab"
    nr = 32
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        h = { "Content-Length" => "0" }
        app(:rack, lambda { |e| [ 200, h, [] ]}) do
          listen "#{host}:#{port}", sndbuf: 2048, rcvbuf: 2048
          client_timeout 1
        end
        client_expire_threshold(32)
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    f = get_tcp_client(host, port)
    s = get_tcp_client(host, port)
    req = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    s.write(req)
    str = ''.dup
    Timeout.timeout(20) { str << s.readpartial(666) until str =~ /\r\n\r\n/ }
    assert_match(%r{keep-alive}, str)
    sleep 2
    abe = tmpfile(%w(abe .err))
    ab_res = `ab -c #{nr} -n 10000 -k http://#{host}:#{port}/ 2>#{abe.path}`
    assert $?.success?, $?.inspect << abe.read
    abe.close!
    assert_match(/Complete requests:\s+10000\n/, ab_res)

    [ f, s ].each do |io|
      assert_raises(Errno::EPIPE,Errno::ECONNRESET) do
        req.each_byte { |b| io.write(b.chr) }
      end
      io.close
    end
  ensure
    quit_wait(pid)
  end

  # test EMFILE handling
  def test_client_expire_desperate
    require_exec "ab"
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        h = { "Content-Length" => "0" }
        queue { worker_threads 1 }
        ru = lambda { |e|
          sleep(0.01) unless e["PATH_INFO"] == "/_"
          [ 200, h, [] ]
        }
        app(:rack, ru) do
          listen "#{host}:#{port}", sndbuf: 2048, rcvbuf: 2048
          client_timeout 1.0
          # FIXME: wbuf creation does not recover from EMFILE/ENFILE
          output_buffering false
          check_client_connection true
        end
        client_expire_threshold 1.0
      end
      stderr_path err.path
    end

    # 1024 is common on old systems, but nowadays Jessie seems to be 65536
    nr = Process.getrlimit(:NOFILE)[0]
    if nr >= 1024
      nr = 1024
      do_rlimit = true
    end

    pid = mkserver(cfg) do
      keep = { $stderr => true, $stdout => true, $stdin => true, @srv => true }
      ObjectSpace.each_object(IO) do |obj|
        next if keep[obj]
        begin
          obj.close unless obj.closed?
        rescue IOError # could be uninitialized
        end
      end
      Process.setrlimit(:NOFILE, nr) if do_rlimit
    end

    f = get_tcp_client(host, port)
    f.write "G"
    s = get_tcp_client(host, port)
    req = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    s.write(req)
    str = ''.dup
    Timeout.timeout(20) { str << s.readpartial(666) until str =~ /\r\n\r\n/ }
    assert_match(%r{keep-alive}, str)
    sleep 1

    assert_operator nr, :>, 666, "increase RLIM_NOFILE (ulimit -n)"
    nr -= 50
    # ignore errors, just beat the crap out of the process
    opts = { out: "/dev/null", err: "/dev/null", close_others: true }
    begin
      pids = 2.times.map do
        Process.spawn(*%W(ab -c #{nr} -n 9999999 -v1 -k
                          http://#{host}:#{port}/), opts)
      end

      re1 = %r{consider raising open file limits}
      re2 = %r{dropping (\d+) of \d+ clients for timeout=\d+}
      Timeout.timeout(30) do
        n = 0
        begin
          buf = File.read(err.path)
          if buf =~ re1 && buf =~ re2
            n += $1.to_i
            break if n >= 2
          end
        end while sleep(0.01)
      end
    ensure
      # don't care for ab errors, they're likely
      pids.each do |_pid|
        Process.kill(:KILL, _pid)
        Process.waitpid2(_pid)
      end
    end

    # this seems to be needed in Debian GNU/kFreeBSD
    linux = !!(RUBY_PLATFORM =~ /linux/)
    sleep(1) unless linux

    [ f, s ].each do |io|
      assert_raises(Errno::EPIPE,Errno::ECONNRESET) do
        req.each_byte do |b|
          io.write(b.chr)
          sleep(0.01) unless linux
        end
      end
      io.close
    end

    # make sure the server still works
    res = Net::HTTP.start(host, port) { |h| h.get("/_") }
    assert_equal 200, res.code.to_i

    errs = File.readlines(err.path).grep(/ERROR/)
    File.truncate(err.path, 0) # avoid error on teardown
    re = %r{consider raising open file limits}
    assert_equal errs.grep(re), errs
  ensure
    quit_wait(pid)
  end
end
