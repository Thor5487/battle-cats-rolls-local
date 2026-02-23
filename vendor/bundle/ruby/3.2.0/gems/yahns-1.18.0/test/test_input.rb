# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'digest/md5'

class TestInput < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  MD5 = lambda do |e|
    input = e["rack.input"]
    tmp = e["rack.tempfiles"]
    case input
    when StringIO, Yahns::StreamInput
      abort "unexpected tempfiles" if tmp && tmp.include?(input)
    when Yahns::TmpIO
      abort "rack.tempfiles missing" unless tmp
      abort "rack.tempfiles missing rack.input" unless tmp.include?(input)
    else
      abort "unrecognized input type: #{input.class}"
    end

    buf = ''.dup
    md5 = Digest::MD5.new
    while input.read(16384, buf)
      md5 << buf
    end
    body = md5.hexdigest
    h = {
      "Content-Length" => body.size.to_s,
      "Content-Type" => 'text/plain',
      "X-Input-Class" => input.class.to_s,
    }
    [ 200, h, [body] ]
  end

  def test_input_timeout_lazybuffer
    stream_input_timeout(:lazy)
  end

  def test_input_timeout_nobuffer
    stream_input_timeout(false)
  end

  def stream_input_timeout(ibtype)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, MD5) do
          listen "#{host}:#{port}"
          input_buffering ibtype
          client_timeout 1
        end
      end
      stderr_path err.path
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    c.write "PUT / HTTP/1.1\r\nContent-Length: 666\r\n\r\n"
    assert_equal c, c.wait(6)
    Timeout.timeout(30) { assert_match %r{HTTP/1\.1 408 }, c.read }
    c.close
  ensure
    quit_wait(pid)
  end

  def input_server(ru, ibtype)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, ru) { listen "#{host}:#{port}"; input_buffering ibtype }
      end
      stderr_path err.path
    end
    pid = mkserver(cfg)
    [ host, port, pid ]
  end

  def test_big_buffer_true
    host, port, pid = input_server(MD5, true)

    c = get_tcp_client(host, port)
    buf = 'hello'
    c.write "PUT / HTTP/1.0\r\nContent-Length: 5\r\n\r\n#{buf}"
    head, body = c.read.split(/\r\n\r\n/)
    assert_match %r{^X-Input-Class: StringIO\r\n}, head
    assert_equal Digest::MD5.hexdigest(buf), body
    c.close

    c = get_tcp_client(host, port)
    buf = 'hello' * 10000
    c.write "PUT / HTTP/1.0\r\nContent-Length: 50000\r\n\r\n#{buf}"
    head, body = c.read.split(/\r\n\r\n/)

    # TODO: shouldn't need CapInput with known Content-Length...
    assert_match %r{^X-Input-Class: Yahns::(CapInput|TmpIO)\r\n}, head
    assert_equal Digest::MD5.hexdigest(buf), body
    c.close

    c = get_tcp_client(host, port)
    c.write "PUT / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n"
    c.write "Transfer-Encoding: chunked\r\n\r\n"
    c.write "#{50000.to_s(16)}\r\n#{buf}\r\n0\r\n\r\n"
    head, body = c.read.split(/\r\n\r\n/)
    assert_match %r{^X-Input-Class: Yahns::CapInput\r\n}, head
    assert_equal Digest::MD5.hexdigest(buf), body
    c.close

  ensure
    quit_wait(pid)
  end

  def test_read_negative_lazy; _read_neg(:lazy); end
  def test_read_negative_nobuffer; _read_neg(false); end

  def _read_neg(ibtype)
    ru = lambda do |env|
      rv = []
      input = env["rack.input"]
      begin
        input.read(-1)
      rescue => e
        rv << e.class.to_s
      end
      rv << input.read
      rv << input.read(1).nil?
      rv = rv.join(",")
      h = { "Content-Length" => rv.size.to_s }
      [ 200, h, [ rv ] ]
    end
    host, port, pid = input_server(ru, ibtype)
    c = get_tcp_client(host, port)
    c.write "PUT / HTTP/1.0\r\nContent-Length: 5\r\n\r\nhello"
    assert_equal c, c.wait(30)
    head, body = c.read.split(/\r\n\r\n/)
    assert_match %r{ 200 OK}, head
    exc, full, final = body.split(/,/)
    assert_equal "hello", full
    assert_equal "ArgumentError", exc
    assert_equal true.to_s, final
    c.close
  ensure
    quit_wait(pid)
  end

  def test_gets_lazy; _gets(:lazy); end
  def test_gets_nobuffer; _gets(false); end

  def _gets(ibtype)
    in_join = lambda do |input|
      rv = []
      while line = input.gets
        rv << line
      end
      rv.join(",")
    end
    ru = lambda do |env|
      rv = in_join.call(env["rack.input"])
      h = { "Content-Length" => rv.size.to_s }
      [ 200, h, [ rv ] ]
    end
    host, port, pid = input_server(ru, ibtype)
    c = get_tcp_client(host, port)
    buf = "a\nb\n\n"
    c.write "PUT / HTTP/1.0\r\nContent-Length: 5\r\n\r\n#{buf}"
    assert_equal c, c.wait(30)
    head, body = c.read.split(/\r\n\r\n/)
    assert_match %r{ 200 OK}, head
    expect = in_join.call(StringIO.new(buf))
    assert_equal expect, body
    c.close
  ensure
    quit_wait(pid)
  end
end
