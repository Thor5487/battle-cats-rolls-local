# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestResponse < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_auto_head
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    str = "HELLO WORLD\n"
    cfg.instance_eval do
      GTL.synchronize do
        app = Rack::Builder.new do
          use Rack::ContentLength
          use Rack::ContentType, "text/plain"
          run(lambda do |env|
            case env['PATH_INFO']
            when '/'; return [ 200, {}, [ str ] ]
            when '/304'; return [ 304, {}, [ str ] ]
            else
              abort 'unsupported'
            end
          end)
        end
        app(:rack, app) { listen "#{host}:#{port}" }
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    s = TCPSocket.new(host, port)
    s.write("HEAD / HTTP/1.0\r\n\r\n")
    assert s.wait(30), "IO wait failed"
    buf = s.read
    assert_match %r{\r\n\r\n\z}, buf
    s.close

    s = TCPSocket.new(host, port)
    s.write("GET /304 HTTP/1.0\r\n\r\n")
    assert s.wait(30), "IO wait failed"
    buf = s.read
    assert_match %r{\r\n\r\n\z}, buf
    assert_match %r{\b304\b}, buf
    s.close
  ensure
    quit_wait(pid)
  end

  def test_response_time_empty_body
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app = Rack::Builder.new do
          use Rack::ContentLength
          use Rack::ContentType, "text/plain"
          run lambda { |_| [ 200, {}, [] ] }
        end
        app(:rack, app) do
          listen "#{host}:#{port}"
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) { |h|
      # warmup request
      res = h.get("/")
      assert_empty res.body

      t0 = Time.now
      nr = 10
      nr.times do
        res = h.get("/")
        assert_empty res.body
      end
      diff = Time.now - t0
      assert_operator diff, :<, (0.200 * nr)
    }
  ensure
    quit_wait(pid)
  end

  def test_response_time_head
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        require 'rack/lobster'
        app = Rack::Builder.new do
          use Rack::Head
          use Rack::ContentLength
          use Rack::ContentType, "text/plain"
          run Rack::Lobster.new
        end
        app(:rack, app) do
          listen "#{host}:#{port}"
        end
      end
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) { |h|
      # warmup request
      res = h.head("/")
      assert_equal 200, res.code.to_i

      t0 = Time.now
      nr = 10
      nr.times do
        res = h.head("/")
        assert_equal 200, res.code.to_i
      end
      diff = Time.now - t0
      assert_operator diff, :<, (0.200 * nr)
    }
  ensure
    quit_wait(pid)
  end
end
