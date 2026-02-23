# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'digest/md5'
require 'rack/file'

class TestOutputBuffering < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  GPLv3 = File.read("COPYING")
  RAND = IO.binread("/dev/urandom", 666) * 119
  dig = Digest::MD5.new
  NR = 1337
  MD5 = Thread.new do
    NR.times { dig << RAND }
    dig.hexdigest
  end

  class BigBody
    def each
      NR.times { yield RAND }
    end
  end

  def test_output_buffer_false_curl
    output_buffer(false, :curl)
  end

  def test_output_buffer_false_http09
    output_buffer(false, :http09)
  end

  def test_output_buffer_true_curl
    output_buffer(true, :curl)
  end

  def test_output_buffer_true_http09
    output_buffer(true, :http09)
  end

  def output_buffer(btype, check_type)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    len = (RAND.size * NR).to_s
    cfg.instance_eval do
      ru = lambda do |e|
        [ 200, {'Content-Length'=>len}, BigBody.new ]
      end
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
          output_buffering btype
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)

    case check_type
    when :curl
      # curl is faster for piping gigantic wads of data than Net::HTTP,
      # and we need to be able to throttle a bit to force output buffering
      c = IO.popen("curl -N -sSf http://#{host}:#{port}/")
      wait_for_full(c)
      dig, nr = md5sum(c)
      c.close
      assert_equal MD5.value, dig.hexdigest
    when :http09
      # HTTP/0.9
      c = get_tcp_client(host, port)
      c.write("GET /\r\n\r\n")
      wait_for_full(c)
      dig, nr = md5sum(c)
      assert_equal(NR * RAND.size, nr)
      c.shutdown
      c.close
      assert_equal MD5.value, dig.hexdigest
    else
      raise "TESTBUG"
    end
  ensure
    quit_wait(pid)
  end

  def md5sum(c)
    dig = Digest::MD5.new
    buf = ''.dup
    nr = 0
    while c.read(8192, buf)
      dig << buf
      nr += buf.bytesize
    end
    [ dig, nr ]
  end

  class BigHeader
    A = "A" * 8192
    def initialize(h)
      @h = h
    end
    def each
      NR.times do |n|
        yield("X-#{n}", A)
      end
      @h.each { |k,v| yield(k,v) }
    end
  end

  def test_big_header
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda do |e|
        case e["PATH_INFO"]
        when "/COPYING"
          Rack::File.new(Dir.pwd).call(e)
          gplv3 = File.open("COPYING")
          def gplv3.each
            raise "SHOULD NOT BE CALLED"
          end
          size = gplv3.size
          len = size.to_s

          ranges = Rack::Utils.respond_to?(:get_byte_ranges) ?
                   Rack::Utils.get_byte_ranges(e['HTTP_RANGE'], size) :
                   Rack::Utils.byte_ranges(e, size)
          status = 200
          h = { "Content-Type" => "text/plain", "Content-Length" => len }
          if ranges && ranges.size == 1
            status = 206
            range = ranges[0]
            h["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{size}"
            size = range.end - range.begin + 1
            len.replace(size.to_s)
          end
          [ status , BigHeader.new(h), gplv3 ]
        when "/"
          h = { "Content-Type" => "text/plain", "Content-Length" => "4" }
          [ 200, BigHeader.new(h), ["BIG\n"] ]
        else
          raise "WTF"
        end
      end
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    threads = []

    # start with just a big header
    threads << Thread.new do
      c = get_tcp_client(host, port)
      c.write "GET / HTTP/1.0\r\n\r\n"
      wait_for_full(c)
      nr = 0
      last = nil
      c.each_line do |line|
        case line
        when %r{\AX-} then nr += 1
        else
          last = line
        end
      end
      assert_equal NR, nr
      assert_equal "BIG\n", last
      c.close
    end

    threads << Thread.new do
      c = get_tcp_client(host, port)
      c.write "GET /COPYING HTTP/1.0\r\n\r\n"
      wait_for_full(c)
      nr = 0
      c.each_line do |line|
        case line
        when %r{\AX-} then nr += 1
        else
          break if line == "\r\n"
        end
      end
      assert_equal NR, nr
      assert_equal GPLv3, c.read
      c.close
    end

    threads << Thread.new do
      c = get_tcp_client(host, port)
      c.write "GET /COPYING HTTP/1.0\r\nRange: bytes=5-46\r\n\r\n"
      wait_for_full(c)
      nr = 0
      c.each_line do |line|
        case line
        when %r{\AX-} then nr += 1
        else
          break if line == "\r\n"
        end
      end
      assert_equal NR, nr
      assert_equal GPLv3[5..46], c.read
      c.close
    end
    threads.each do |t|
      assert_equal t, t.join(30)
      assert_nil t.value
    end
  ensure
    quit_wait(pid)
  end

  def test_client_timeout
    err = @err
    skip_skb_mem
    apperr = tmpfile(%w(app .err))
    cfg = Yahns::Config.new
    size = RAND.size * NR
    host, port = @srv.addr[3], @srv.addr[1]
    re = /timeout on :wait_writable after 0\.1s$/
    cfg.instance_eval do
      ru = lambda do |e|
        if e["PATH_INFO"] == "/bh"
          h = { "Content-Type" => "text/plain", "Content-Length" => "4" }
          [ 200, BigHeader.new(h), ["BIG\n"] ]
        else
          [ 200, {'Content-Length' => size.to_s }, BigBody.new ]
        end
      end
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
          output_buffering false
          client_timeout 0.1
          logger(Logger.new(apperr.path))
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)

    wait_for_timeout_msg = lambda do
      Timeout.timeout(6) do
        sleep(0.01) until File.readlines(apperr.path).grep(re).size == 2
      end
    end
    threads = []
    threads << Thread.new do
      c = get_tcp_client(host, port)
      c.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
      wait_for_full(c)
      wait_for_timeout_msg.call
      assert_operator c.nread, :>, 0
      c
    end

    threads << Thread.new do
      c = get_tcp_client(host, port)
      c.write("GET /bh HTTP/1.1\r\nHost: example.com\r\n\r\n")
      wait_for_full(c)
      wait_for_timeout_msg.call
      assert_operator c.nread, :>, 0
      c
    end
    threads.each { |t| t.join(10) }
    assert_operator size, :>, threads[0].value.read.size
    assert_operator size, :>, threads[1].value.read.size
    msg = File.readlines(apperr.path)
    msg = msg.grep(re)
    assert_equal 2, msg.size
    threads.each { |t| t.value.close }
  ensure
    apperr.close! if apperr
    quit_wait(pid)
  end

  def test_hijacked
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      ru = lambda do |e|
        h = {
          "Content-Type" => "text/plain",
          "Content-Length" => "4",
          "rack.hijack" => proc { |x| x.write("HIHI"); x.close },
        }
        body = Object.new
        def body.each; abort "body#each should not be used"; end
        [ 200, BigHeader.new(h), body ]
      end
      GTL.synchronize do
        app(:rack, ru) do
          listen "#{host}:#{port}"
        end
      end
      stderr_path err.path
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    c.write "GET / HTTP/1.0\r\n\r\n"
    wait_for_full(c)
    nr = 0
    last = nil
    c.each_line do |line|
      case line
      when %r{\AX-} then nr += 1
      else
        last = line
      end
    end
    assert_equal NR, nr
    assert_equal "HIHI", last
    c.close
  ensure
    quit_wait(pid)
  end
end if `which curl 2>/dev/null`.strip =~ /curl/
