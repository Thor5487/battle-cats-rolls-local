# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative 'server_helper'

class TestAutoChunk < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_auto_head
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app = Rack::Builder.new do
          use Rack::ContentType, "text/plain"
          run(lambda do |env|
            case env['PATH_INFO']
            when '/204'
              [ 204, {}, [] ]
            else
              [ 200, {}, %w(a b c) ]
            end
          end)
        end
        app(:rack, app) { listen "#{host}:#{port}" }
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    s = TCPSocket.new(host, port)
    s.write("GET / HTTP/1.0\r\n\r\n")
    assert s.wait(30), "IO wait failed"
    buf = s.read
    assert_match %r{\r\n\r\nabc\z}, buf
    s.close

    s = TCPSocket.new(host, port)
    s.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
    buf = ''.dup
    Timeout.timeout(30) do
      until buf =~ /\r\n\r\n1\r\na\r\n1\r\nb\r\n1\r\nc\r\n0\r\n\r\n\z/
        buf << s.readpartial(16384)
      end
    end
    assert_match(%r{^Transfer-Encoding: chunked\r\n}, buf)
    s.close

    Net::HTTP.start(host, port) do |http|
      req = Net::HTTP::Get.new("/")
      res = http.request(req)
      assert_equal 200, res.code.to_i
      assert_equal 'abc', res.body
    end

    s = TCPSocket.new(host, port)
    s.write("GET /204 HTTP/1.1\r\nHost: example.com\r\n\r\n")
    buf = s.readpartial(1024)
    assert_match %r{\r\n\r\n\z}, buf
    refute_match %r{^Transfer-Encoding}i, buf
    assert_match %r{^Connection: keep-alive\r\n}, buf
    assert_nil IO.select([s], nil, nil, 1), 'connection persists..'

    # maek sure another on the same connection works
    s.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
    buf = s.readpartial(1024)
    assert_match %r{\AHTTP/1\.1 200}, buf
    assert_match(%r{^Transfer-Encoding: chunked\r\n}, buf)
    s.close
  ensure
    quit_wait(pid)
  end
end
