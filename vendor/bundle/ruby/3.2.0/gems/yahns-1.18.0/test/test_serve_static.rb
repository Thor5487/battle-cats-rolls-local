# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'server_helper'
require 'rack/file'

class TestServeStatic < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_serve_static
    tmpdir = yahns_mktmpdir
    sock = "#{tmpdir}/sock"
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, Rack::File.new(Dir.pwd)) {
          listen sock
          listen "#{host}:#{port}"
        }
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    gplv3 = File.read("COPYING")
    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/COPYING"))
      assert_equal gplv3, res.body

      req = Net::HTTP::Get.new("/COPYING", "Range" => "bytes=5-46")
      res = http.request(req)
      assert_match %r{bytes 5-46/\d+\z}, res["Content-Range"]
      assert_equal gplv3[5..46], res.body
    end

    # ensure sendfile works on Unix sockets
    s = UNIXSocket.new(sock)
    s.write "GET /COPYING\r\n\r\n"
    assert_equal gplv3, Timeout.timeout(30) { s.read }
    s.close
  ensure
    quit_wait(pid)
    FileUtils.rm_rf tmpdir
  end

  def test_serve_static_blocked_header
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, Rack::File.new(Dir.pwd)) { listen "#{host}:#{port}" }
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg) do
      $_tw_blocked = 0
      $_tw_block_on = [1]
      Yahns::HttpClient.__send__(:include, TrywriteBlocked)
    end
    gplv3 = File.read("COPYING")
    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/COPYING"))
      assert_equal gplv3, res.body

      req = Net::HTTP::Get.new("/COPYING", "Range" => "bytes=5-46")
      res = http.request(req)
      assert_equal gplv3[5..46], res.body
    end
  ensure
    quit_wait(pid)
  end

  def mksparse(tmpdir)
    sparse = "#{tmpdir}/sparse"
    off = 100 * 1024 * 1024
    File.open(sparse, "w") do |fp|
      fp.sysseek(off)
      fp.syswrite '.'
    end
    [ off + 1, sparse ]
  end

  class ToPathClose
    attr_reader :closed_p

    def initialize(app, tmpdir)
      @app = app
      @tmpdir = tmpdir
      @log = "#@tmpdir/to_path--close"
      @body = nil
      @closed_p = false
    end

    def call(env)
      s, h, b = @app.call(env)
      @body = b
      [ s, h, self ]
    end

    def each
      raise "ToPathClose#each should not be called"
    end

    def to_path
      File.open(@log, "a") { |fp| fp.write("to_path\n") }
      "#@tmpdir/sparse"
    end

    def close
      File.open(@log, "a") { |fp| fp.write("close\n") }
      raise "Double close" if @closed_p
      @closed_p = true
      nil
    end
  end

  def test_aborted_sendfile_closes_opened_path
    tmpdir = yahns_mktmpdir
    mksparse(tmpdir)
    fifo = "#{tmpdir}/to_path--close"
    assert system("mkfifo", fifo), "mkfifo"
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        app = Rack::Builder.new do
          use ToPathClose, tmpdir
          run Rack::File.new(tmpdir)
        end
        app(:rack, app) { listen "#{host}:#{port}" }
        stderr_path err.path
      end
    end
    c = get_tcp_client(host, port)
    c.write "GET /sparse HTTP/1.1\r\nHost: example.com\r\n\r\n"
    assert_equal "to_path\n", File.read(fifo)
    wait_for_full(c)
    assert_nil c.close
    Timeout.timeout(30) { assert_equal "close\n", File.read(fifo) }
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  def test_truncated_sendfile
    tmpdir = yahns_mktmpdir
    size, sparse = mksparse(tmpdir)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        app(:rack, Rack::File.new(tmpdir)) { listen "#{host}:#{port}" }
        stderr_path err.path
      end
    end
    c = get_tcp_client(host, port)
    c.write "GET /sparse HTTP/1.1\r\nHost: example.com\r\n\r\n"
    wait_for_full(c)
    File.truncate(sparse, 5)
    buf = Timeout.timeout(60) { c.read }
    c.close
    assert_operator buf.size, :<, size
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  def test_expanded_sendfile
    tmpdir = yahns_mktmpdir
    size, sparse = mksparse(tmpdir)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        app(:rack, Rack::File.new(tmpdir)) { listen "#{host}:#{port}" }
        stderr_path err.path
      end
    end
    c = get_tcp_client(host, port)
    c.write "GET /sparse\r\n\r\n"
    wait_for_full(c)

    File.open(sparse, "w") do |fp|
      fp.sysseek(size * 2)
      fp.syswrite '.'
    end
    Timeout.timeout(60) do
      bytes = IO.copy_stream(c, "/dev/null")
      assert_equal bytes, size
      assert_raises(EOFError) { c.readpartial 1 }
    end
    c.close
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end
end
