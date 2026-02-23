# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestServer < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper

  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_single_process
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda { |_| [ 200, {'Content-Length'=>'2'}, ['HI'] ] }
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    run_client(host, port) { |res| assert_equal "HI", res.body }
    c = get_tcp_client(host, port)

    # test pipelining
    r = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    c.write(r + r)
    buf = ''.dup
    Timeout.timeout(10) do
      until buf =~ /HI.+HI/m
        buf << c.readpartial(4096)
      end
    end

    # trickle pipelining
    c.write(r + "GET ")
    buf = ''.dup
    Timeout.timeout(10) do
      until buf =~ /HI\z/
        buf << c.readpartial(4096)
      end
    end
    c.write("/ HTTP/1.1\r\nHost: example.com\r\n\r\n")
    Timeout.timeout(10) do
      until buf =~ /HI.+HI/m
        buf << c.readpartial(4096)
      end
    end
    Process.kill(:QUIT, pid)
    "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".each_byte do |x|
      sleep(0.01)
      c.write(x.chr)
    end
    buf = Timeout.timeout(30) { c.read }
    assert_match(/Connection: close/, buf)
    _, status = Timeout.timeout(10) { Process.waitpid2(pid) }
    assert status.success?, status.inspect
    c.close
  end

  def test_input_body_true; input_body(true); end
  def test_input_body_false; input_body(false); end
  def test_input_body_lazy; input_body(:lazy); end

  def input_body(btype)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda {|e|[ 200, {'Content-Length'=>'2'},[e["rack.input"].read]]}
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
          input_buffering btype
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    buf = "PUT / HTTP/1.0\r\nContent-Length: 2\r\n\r\nHI"
    c.write(buf)
    IO.select([c], nil, nil, 5)
    rv = c.read(666)
    head, body = rv.split(/\r\n\r\n/)
    assert_match(%r{^Content-Length: 2\r\n}, head)
    assert_equal "HI", body, "#{rv.inspect} - #{btype.inspect}"
    c.close

    # pipelined oneshot
    buf = "PUT / HTTP/1.1\r\nContent-Length: 2\r\n\r\nHI"
    c = get_tcp_client(host, port)
    c.write(buf + buf)
    buf = ''.dup
    Timeout.timeout(10) do
      until buf =~ /HI.+HI/m
        buf << c.readpartial(4096)
      end
    end
    assert buf.gsub!(/Date:[^\r\n]+\r\n/, ""), "kill differing Date"
    rv = buf.sub!(/\A(HTTP.+?\r\n\r\nHI)/m, "")
    first = $1
    assert rv
    assert_equal first, buf

    # pipelined trickle
    buf = "PUT / HTTP/1.1\r\nContent-Length: 5\r\n\r\nHIBYE"
    (buf + buf).each_byte do |b|
      c.write(b.chr)
      sleep(0.01) if b.chr == ":"
      Thread.pass
    end
    buf = ''.dup
    Timeout.timeout(10) do
      until buf =~ /HIBYE.+HIBYE/m
        buf << c.readpartial(4096)
      end
    end
    assert buf.gsub!(/Date:[^\r\n]+\r\n/, ""), "kill differing Date"
    rv = buf.sub!(/\A(HTTP.+?\r\n\r\nHIBYE)/m, "")
    first = $1
    assert rv
    assert_equal first, buf
  ensure
    c.close if c
    quit_wait(pid)
  end

  def test_trailer_true; trailer(true); end
  def test_trailer_false; trailer(false); end
  def test_trailer_lazy; trailer(:lazy); end
  def test_slow_trailer_true; trailer(true, 0.02); end
  def test_slow_trailer_false; trailer(false, 0.02); end
  def test_slow_trailer_lazy; trailer(:lazy, 0.02); end

  def trailer(btype, delay = false)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda do |e|
        body = e["rack.input"].read
        s = e["HTTP_XBT"] + "\n" + body
        [ 200, {'Content-Length'=>s.size.to_s}, [ s ] ]
      end
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
          input_buffering btype
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    buf = "PUT / HTTP/1.0\r\nTrailer:xbt\r\nTransfer-Encoding: chunked\r\n\r\n"
    c.write(buf)
    xbt = btype.to_s
    sleep(delay) if delay
    c.write(sprintf("%x\r\n", xbt.size))
    sleep(delay) if delay
    c.write(xbt)
    sleep(delay) if delay
    c.write("\r\n")
    sleep(delay) if delay
    c.write("0\r\nXBT: ")
    sleep(delay) if delay
    c.write("#{xbt}\r\n\r\n")
    IO.select([c], nil, nil, 5000) or raise "timed out"
    rv = c.read(666)
    _, body = rv.split(/\r\n\r\n/)
    a, b = body.split(/\n/)
    assert_equal xbt, a
    assert_equal xbt, b
  ensure
    c.close if c
    quit_wait(pid)
  end

  def test_check_client_connection
    tmpdir = yahns_mktmpdir
    sock = "#{tmpdir}/sock"
    unix_srv = UNIXServer.new(sock)
    msgs = %w(ZZ zz)
    err = @err
    cfg = Yahns::Config.new
    bpipe = cloexec_pipe
    cfg.instance_eval do
      ru = lambda { |e|
        case e['PATH_INFO']
        when '/sleep'
          a = Object.new
          a.instance_variable_set(:@bpipe, bpipe)
          a.instance_variable_set(:@msgs, msgs)
          def a.each
            @msgs.each do |msg|
              yield @bpipe[0].read(msg.size)
            end
          end
        when '/cccfail'
          # we should not get here if check_client_connection worked
          abort "CCCFAIL"
        else
          a = %w(HI)
        end
        [ 200, {'Content-Length'=>'2'}, a ]
      }
      GTL.synchronize {
        app(:rack, ru) {
          listen sock
          check_client_connection true
          # needed to avoid concurrency with check_client_connection
          queue { worker_threads 1 }
          output_buffering false
        }
      }
      logger(Logger.new(err.path))
    end
    srv = Yahns::Server.new(cfg)

    # ensure we set worker_threads correctly
    eggs = srv.instance_variable_get(:@config).qeggs
    assert_equal 1, eggs.size
    assert_equal 1, eggs.first[1].instance_variable_get(:@worker_threads)

    pid = xfork do
      bpipe[1].close
      ENV["YAHNS_FD"] = unix_srv.fileno.to_s
      unix_srv.autoclose = false
      srv.start.join
    end
    bpipe[0].close
    a = UNIXSocket.new(sock)
    b = UNIXSocket.new(sock)
    a.write("GET /sleep HTTP/1.0\r\n\r\n")
    r = IO.select([a], nil, nil, 4)
    assert r, "nothing ready"
    assert_equal a, r[0][0]
    buf = a.read(8)
    assert_equal "HTTP/1.1", buf

    # hope the kernel sees this before it sees the bpipe ping-ponging below
    b.write("GET /cccfail HTTP/1.0\r\n\r\n")
    b.shutdown
    b.close

    # ping-pong a bit to stall the server
    msgs.each do |msg|
      bpipe[1].write(msg)
      Timeout.timeout(10) { buf << a.readpartial(10) until buf =~ /#{msg}/ }
    end
    bpipe[1].close
    assert_equal msgs.join, buf.split(/\r\n\r\n/)[1]

    # do things still work?
    c = UNIXSocket.new(sock)
    c.write "GET /\r\n\r\n"
    assert_equal "HI", c.read
    c.close
    a.close
  rescue => e
    warn e.class
    warn e.message
    warn e.backtrace.join("\n")
  ensure
    unix_srv.close
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  def test_mp
    pid, host, port = new_mp_server
    wpid = nil
    run_client(host, port) do |res|
      wpid ||= res.body.to_i
    end
  ensure
    quit_wait(pid)
    if wpid
      assert_raises(Errno::ESRCH) { Process.kill(:KILL, wpid) }
      assert_raises(Errno::ECHILD) { Process.waitpid2(wpid) }
    end
  end

  def test_mp_worker_die
    pid, host, port = new_mp_server
    wpid1 = wpid2 = nil
    run_client(host, port) do |res|
      wpid1 ||= res.body.to_i
    end
    Process.kill(:QUIT, wpid1)
    poke_until_dead(wpid1)
    run_client(host, port) do |res|
      wpid2 ||= res.body.to_i
    end
    refute_equal wpid2, wpid1
  ensure
    quit_wait(pid)
    assert_raises(Errno::ESRCH) { Process.kill(:KILL, wpid2) } if wpid2
  end

  def test_mp_dead_parent
    pid, host, port = new_mp_server(1)
    wpid = nil
    run_client(host, port) do |res|
      wpid ||= res.body.to_i
    end
    Process.kill(:KILL, pid)
    _, status = Process.waitpid2(pid)
    assert status.signaled?, status.inspect
    poke_until_dead(wpid)
  end

  def run_client(host, port)
    c = get_tcp_client(host, port)
    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      assert_equal "keep-alive", res["Connection"]
      yield res
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      assert_equal "keep-alive", res["Connection"]
      yield res
    end
    c.write "GET / HTTP/1.0\r\n\r\n"
    res = Timeout.timeout(10) { c.read }
    head, _ = res.split(/\r\n\r\n/)
    head = head.split(/\r\n/)
    assert_equal "HTTP/1.1 200 OK", head[0]
    assert_equal "Connection: close", head[-1]
    c.close
  end

  def new_mp_server(nr = 2)
    ru = @ru = tmpfile(%w(config .ru))
    @ru.puts('a = $$.to_s')
    @ru.puts('run lambda { |_| [ 200, {"Content-Length"=>a.size.to_s},[a]]}')
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      worker_processes nr
      GTL.synchronize { app(:rack, ru.path) { listen "#{host}:#{port}" } }
      logger(Logger.new(File.open(err.path, "a")))
    end
    pid = mkserver(cfg)
    [ pid, host, port ]
  end

  def test_nonpersistent
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda { |_| [ 200, {'Content-Length'=>'2'}, ['HI'] ] }
      GTL.synchronize {
        app(:rack, ru) {
          listen "#{host}:#{port}"
          persistent_connections false
        }
      }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    c.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
    buf = Timeout.timeout(10) { c.read }
    assert_match(/Connection: close/, buf)
    c.close
  ensure
    quit_wait(pid)
  end

  def test_ttin_ttou
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    ru = lambda { |_|
      b = "#$$"
      [ 200, {'Content-Length'=>b.size.to_s}, [b] ]
    }
    cfg.instance_eval do
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      worker_processes 1
      stderr_path err.path
    end
    pid = mkserver(cfg)

    read_pid = lambda do
      c = get_tcp_client(host, port)
      c.write("GET /\r\n\r\n")
      body = Timeout.timeout(10) { c.read }
      c.close
      assert_match(/\A\d+\z/, body)
      body
    end

    orig_worker_pid = read_pid.call.to_i
    assert_equal 1, Process.kill(0, orig_worker_pid)

    Process.kill(:TTOU, pid)
    poke_until_dead(orig_worker_pid)

    Process.kill(:TTIN, pid)
    second_worker_pid = read_pid.call.to_i

    # PID recycling is rare, hope it doesn't fail here
    refute_equal orig_worker_pid, second_worker_pid
  ensure
    quit_wait(pid)
  end

  def test_mp_hooks
    err = @err
    out = tmpfile(%w(mp_hooks .out))
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda {|_|x="#$$";[200,{'Content-Length'=>x.size.to_s },[x]]}
      GTL.synchronize {
        app(:rack, ru) {
          listen "#{host}:#{port}"
          persistent_connections false
          atfork_child { warn "INFO hihi from app.atfork_child" }
        }
        worker_processes(1) do
          atfork_child { puts "af #$$ worker is running" }
          atfork_prepare { puts "af #$$ parent about to spawn" }
          atfork_parent { puts "af #$$ parent done spawning" }
        end
      }
      stderr_path err.path
      stdout_path out.path
    end
    master_pid = pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    c.write("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
    buf = Timeout.timeout(10) { c.read }
    c.close
    head, body = buf.split(/\r\n\r\n/)
    assert_match(/200 OK/, head)
    assert_match(/\A\d+\z/, body)
    worker_pid = body.to_i

    # ensure atfork_parent has run
    quit_wait(master_pid)
    master_pid = nil

    lines = out.readlines.map!(&:chomp!)
    out.close!

    assert_match %r{INFO hihi from app\.atfork_child}, File.read(err.path)

    assert_equal 3, lines.size, lines.join("\n")
    assert_equal("af #{pid} parent about to spawn", lines.shift)

    # child/parent ordering is not guaranteed
    assert_equal 1, lines.grep(/\Aaf #{pid} parent done spawning\z/).size
    assert_equal 1, lines.grep(/\Aaf #{worker_pid} worker is running\z/).size
  ensure
    quit_wait(master_pid)
  end

  def test_mp_hooks_worker_nr
    err = @err
    out = tmpfile(%w(mp_hooks .out))
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda {|_|x="#$$";[200,{'Content-Length'=>x.size.to_s },[x]]}
      GTL.synchronize {
        app(:rack, ru) {
          listen "#{host}:#{port}"
          persistent_connections false
          atfork_child { |nr| warn "INFO hihi.#{nr} from app.atfork_child" }
        }
        worker_processes(1) do
          atfork_child { |nr| puts "af.#{nr} #$$ worker is running" }
          atfork_prepare { |nr| puts "af.#{nr} #$$ parent about to spawn" }
          atfork_parent { |nr| puts "af.#{nr} #$$ parent done spawning" }
        end
      }
      stderr_path err.path
      stdout_path out.path
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    c.write("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
    buf = Timeout.timeout(10) { c.read }
    c.close
    head, body = buf.split(/\r\n\r\n/)
    assert_match(/200 OK/, head)
    assert_match(/\A\d+\z/, body)
    worker_pid = body.to_i
    lines = out.readlines.map!(&:chomp!)
    out.close!

    assert_match %r{INFO hihi\.0 from app\.atfork_child}, File.read(err.path)
    assert_equal 3, lines.size
    assert_equal("af.0 #{pid} parent about to spawn", lines.shift)

    # child/parent ordering is not guaranteed
    assert_equal 1,
        lines.grep(/\Aaf\.0 #{pid} parent done spawning\z/).size
    assert_equal 1,
        lines.grep(/\Aaf\.0 #{worker_pid} worker is running\z/).size
  ensure
    quit_wait(pid)
  end

  def test_pidfile_usr2
    tmpdir = yahns_mktmpdir
    pidf = "#{tmpdir}/pid"
    old = "#{pidf}.oldbin"
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize {
        app(:rack, lambda { |_| [ 200, {}, [] ] }) { listen "#{host}:#{port}" }
        pid pidf
      }
      stderr_path err.path
    end
    pid = mkserver(cfg) do
      Yahns::START[0] = "sh"
      Yahns::START[:argv] = [ '-c', "echo $$ > #{pidf}; sleep 10" ]
    end

    # ensure server is running
    c = get_tcp_client(host, port)
    c.write("GET / HTTP/1.0\r\n\r\n")
    buf = Timeout.timeout(10) { c.read }
    assert_match(/Connection: close/, buf)
    c.close

    assert_equal pid, File.read(pidf).to_i
    before = File.stat(pidf)

    # start the upgrade
    Process.kill(:USR2, pid)
    Timeout.timeout(10) { sleep(0.01) until File.exist?(old) }
    after = File.stat(old)
    assert_equal after.ino, before.ino
    Timeout.timeout(10) { sleep(0.01) until File.exist?(pidf) }
    new = File.read(pidf).to_i
    refute_equal pid, new

    # abort the upgrade (just wait for it to finish)
    Process.kill(:TERM, new)
    poke_until_dead(new)

    # ensure reversion is OK
    Timeout.timeout(10) { sleep(0.01) while File.exist?(old) }
    after = File.stat(pidf)
    assert_equal before.ino, after.ino
    assert_equal before.mtime, after.mtime
    assert_equal pid, File.read(pidf).to_i

    lines = File.readlines(err.path).grep(/ERROR/)
    assert_equal 1, lines.size
    assert_match(/reaped/, lines[0], lines)
    File.truncate(err.path, 0)
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  module MockSwitchUser
    def self.included(cls)
      cls.__send__(:remove_method, :switch_user)
      cls.__send__(:alias_method, :switch_user, :mock_switch_user)
    end

    def mock_switch_user(user, group = nil)
      $yahns_user = [ $$, user, group ]
    end
  end

  def test_user_no_workers
    refute defined?($yahns_user), "$yahns_user global should be undefined"
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda do |_|
        b = $yahns_user.inspect
        [ 200, {'Content-Length'=>b.size.to_s }, [b] ]
      end
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      user "nobody"
      stderr_path err.path
    end
    pid = mkserver(cfg) { Yahns::Server.__send__(:include, MockSwitchUser) }
    expect = [ pid, "nobody", nil ].inspect
    run_client(host, port) { |res| assert_equal expect, res.body }
    refute defined?($yahns_user), "$yahns_user global should be undefined"
  ensure
    quit_wait(pid)
  end

  def test_user_workers
    refute defined?($yahns_user), "$yahns_user global should be undefined"
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda do |_|
        b = $yahns_user.inspect
        [ 200, {'Content-Length'=>b.size.to_s, 'X-Pid' => "#$$" }, [b] ]
      end
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      user "nobody"
      stderr_path err.path
      worker_processes 1
    end
    pid = mkserver(cfg) { Yahns::Server.__send__(:include, MockSwitchUser) }
    run_client(host, port) do |res|
      worker_pid = res["X-Pid"].to_i
      assert_operator worker_pid, :>, 0
      refute_equal pid, worker_pid
      refute_equal $$, worker_pid
      expect = [ worker_pid, "nobody", nil ].inspect
      assert_equal expect, res.body
    end
    refute defined?($yahns_user), "$yahns_user global should be undefined"
  ensure
    quit_wait(pid)
  end

  def test_working_directory
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    ru = lambda { |_|
      [ 200, {'Content-Length'=>Dir.pwd.size.to_s }, [Dir.pwd] ]
    }
    yahns_mktmpdir do |tmpdir|
      begin
        pid = mkserver(cfg) do
          $LOAD_PATH << File.expand_path("lib")
          cfg.instance_eval do
            working_directory tmpdir
            app(:rack, ru) { listen "#{host}:#{port}" }
            stderr_path err.path
          end
        end
        refute_equal Dir.pwd, tmpdir
        Net::HTTP.start(host, port) do |http|
          assert_equal tmpdir, http.request(Net::HTTP::Get.new("/")).body
        end
      ensure
        quit_wait(pid)
      end
    end
  end

  def test_errors
    tmpdir = yahns_mktmpdir
    sock = "#{tmpdir}/sock"
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    re = tmpfile(%w(rack .errors))
    ru = lambda { |e|
      e["rack.errors"].write "INFO HIHI\n"
      [ 200, {'Content-Length'=>'2' }, %w(OK) ]
    }
    cfg.instance_eval do
      GTL.synchronize {
        app(:rack, ru) {
          listen "#{host}:#{port}"
          errors re.path
        }
        app(:rack, ru) { listen sock }
      }
      stderr_path err.path
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) do |http|
      assert_equal "OK", http.request(Net::HTTP::Get.new("/")).body
    end
    assert_equal "INFO HIHI\n", re.read

    c = UNIXSocket.new(sock)
    c.write "GET /\r\n\r\n"
    assert_equal c, c.wait(30)
    assert_equal "OK", c.read
    c.close
    assert_match %r{INFO HIHI}, File.read(err.path)
  ensure
    re.close!
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  def test_persistent_shutdown_timeout; _persistent_shutdown(nil); end
  def test_persistent_shutdown_timeout_mp; _persistent_shutdown(1); end

  def _persistent_shutdown(nr_workers)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      ru = lambda { |e| [ 200, {'Content-Length'=>'2'}, %w(OK) ] }
      cfg.instance_eval do
        app(:rack, ru) { listen "#{host}:#{port}" }
        stderr_path err.path
        shutdown_timeout 1
        worker_processes(nr_workers) if nr_workers
      end
    end
    c = get_tcp_client(host, port)
    c.write "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    assert_equal c, c.wait(30)
    buf = ''.dup
    re = /\r\n\r\nOK\z/
    Timeout.timeout(30) do
      begin
        buf << c.readpartial(666)
      end until re =~ buf
    end
    refute_match %r{Connection: close}, buf
    assert_nil c.wait(0.001), "connection should still be alive"
    Process.kill(:QUIT, pid)
    _, status = Timeout.timeout(5) { Process.waitpid2(pid) }
    assert status.success?, status.inspect
    assert_nil c.read(666)
  end

  def test_slow_shutdown_timeout; _slow_shutdown(nil); end
  def test_slow_shutdown_timeout_mp; _slow_shutdown(1); end

  def _slow_shutdown(nr_workers)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      ru = lambda { |e| [ 200, {'Content-Length'=>'2'}, %w(OK) ] }
      cfg.instance_eval do
        app(:rack, ru) { listen "#{host}:#{port}" }
        stderr_path err.path
        worker_processes(nr_workers) if nr_workers
      end
    end
    c = get_tcp_client(host, port)
    c.write 'G'
    100000.times { Thread.pass }
    Process.kill(:QUIT, pid)
    "ET / HTTP/1.1\r\nHost: example.com\r\n\r\n".each_byte do |x|
      Thread.pass
      c.write(x.chr)
      Thread.pass
    end
    assert_equal c, c.wait(30)
    buf = ''.dup
    re = /\r\n\r\nOK\z/
    Timeout.timeout(30) do
      begin
        buf << c.readpartial(666)
      end until re =~ buf
    end
    c.close
    _, status = Timeout.timeout(5) { Process.waitpid2(pid) }
    assert status.success?, status.inspect
  end

  def test_before_exec
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    ru = lambda { |e| [ 200, {'Content-Length'=>'2' }, %w(OK) ] }
    tmp = tmpfile(%w(exec .pid))
    x = "echo $$ >> #{tmp.path}"
    pid = mkserver(cfg) do
      cfg.instance_eval do
        app(:rack, ru) { listen "#{host}:#{port}" }
        before_exec do |exec_cmd|
          exec_cmd.replace(%W(/bin/sh -c #{x}))
        end
        stderr_path err.path
      end
    end

    # did we start properly?
    Net::HTTP.start(host, port) do |http|
      assert_equal "OK", http.request(Net::HTTP::Get.new("/")).body
    end

    Process.kill(:USR2, pid)
    Timeout.timeout(30) { sleep(0.01) until tmp.size > 0 }
    buf = tmp.read
    assert_match %r{\A\d+}, buf
    exec_pid = buf.to_i
    poke_until_dead exec_pid

    # ensure it recovered
    Net::HTTP.start(host, port) do |http|
      assert_equal "OK", http.request(Net::HTTP::Get.new("/")).body
    end
    assert_match %r{reaped}, err.read
    err.truncate(0)
  ensure
    tmp.close!
    quit_wait(pid)
  end

  def test_app_controls_close
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        ru = lambda { |env|
          h = { 'Content-Length' => '2' }
          if env["PATH_INFO"] =~ %r{\A/(.+)}
            h["Connection"] = $1
          end
          [ 200, h, ['HI'] ]
        }
        app(:rack, ru) { listen "#{host}:#{port}" }
        stderr_path err.path
      end
    end
    c = get_tcp_client(host, port)

    # normal response
    c.write "GET /keep-alive HTTP/1.1\r\nHost: example.com\r\n\r\n"
    buf = ''.dup
    Timeout.timeout(30) do
      buf << c.readpartial(4096) until buf =~ /HI\z/
    end
    assert_match %r{^Connection: keep-alive}, buf
    assert_raises(Errno::EAGAIN,IO::WaitReadable) { c.read_nonblock(666) }

    # we allow whatever in the response, but don't send it
    c.write "GET /whatever HTTP/1.1\r\nHost: example.com\r\n\r\n"
    buf = ''.dup
    Timeout.timeout(30) do
      buf << c.readpartial(4096) until buf =~ /HI\z/
    end
    assert_match %r{^Connection: keep-alive}, buf
    assert_raises(Errno::EAGAIN,IO::WaitReadable) { c.read_nonblock(666) }

    c.write "GET /close HTTP/1.1\r\nHost: example.com\r\n\r\n"
    buf = ''.dup
    Timeout.timeout(30) do
      buf << c.readpartial(4096) until buf =~ /HI\z/
    end
    assert_match %r{^Connection: close}, buf
    assert_equal c, IO.select([c], nil, nil, 30)[0][0]
    assert_raises(EOFError) { c.readpartial(666) }
    c.close
  ensure
    quit_wait(pid)
  end

  def test_inherit_too_many
    err = @err
    s2 = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda { |_| [ 200, {'Content-Length'=>'2'}, ['HI'] ] }
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg, @srv) do
      s2.autoclose = false
      ENV["YAHNS_FD"] = "#{@srv.fileno},#{s2.fileno}"
    end
    run_client(host, port) { |res| assert_equal "HI", res.body }
    th = Thread.new do
      c = s2.accept
      c.readpartial(1234)
      c.write "HTTP/1.0 666 OK\r\n\r\nGO AWAY"
      c.close
      :OK
    end
    Thread.pass
    s2host, s2port = s2.addr[3], s2.addr[1]
    Net::HTTP.start(s2host, s2port) do |http|
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 666, res.code.to_i
      assert_equal "GO AWAY", res.body
    end
    assert_equal :OK, th.value
    tmpc = TCPSocket.new(s2host, s2port)
    a2 = s2.accept
    assert_nil IO.select([a2], nil, nil, 0.05)
    tmpc.close
    assert_nil a2.read(1)
    a2.close
    s2.close
  ensure
    quit_wait(pid)
  end

  def test_inherit_tcp_nodelay_set
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    @srv.setsockopt(:IPPROTO_TCP, :TCP_NODELAY, 0)
    assert_equal 0, @srv.getsockopt(:IPPROTO_TCP, :TCP_NODELAY).int
    cfg.instance_eval do
      ru = lambda { |_| [ 200, { 'Content-Length' => '2' } , [ 'HI' ] ] }
      GTL.synchronize { app(:rack, ru) { listen "#{host}:#{port}" } }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg, @srv) { ENV["YAHNS_FD"] = "#{@srv.fileno}" }
    run_client(host, port) { |res| assert_equal "HI", res.body }

    # TCP socket option is shared at file level, not FD level:
    assert_equal 1, @srv.getsockopt(:IPPROTO_TCP, :TCP_NODELAY).int
  ensure
    quit_wait(pid)
  end
end
