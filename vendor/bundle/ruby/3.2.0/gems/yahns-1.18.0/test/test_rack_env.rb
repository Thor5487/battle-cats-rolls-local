# Copyright (C) 2017 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative 'server_helper'
require 'rack'

class TestRackEnv < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_rack_env_logger
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      stderr_path err.path
      GTL.synchronize do
        app = Rack::Builder.new do
          use Rack::Lint # ensure Lint passes
          run(lambda do |env|
            logger = env['rack.logger']
            %w(SERVER_NAME SERVER_PORT rack.url_scheme).each do |k|
              logger.info("#{k}=#{env[k].inspect}")
            end
            [ 200, [ %w(Content-Length 3), %w(Content Type text/plain)],
             [ "OK\n" ] ]
          end)
        end
        app(:rack, app.to_app) { listen "#{host}:#{port}" }
      end
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      assert_equal "OK\n", res.body
      txt = File.read(err.path)
      assert_match %r{\srack\.url_scheme=#{Regexp.escape('http'.inspect)}\s}s,
                   txt
      assert_match %r{\sSERVER_NAME=#{Regexp.escape(host.inspect)}\s}s, txt
      assert_match %r{\sSERVER_PORT=#{Regexp.escape(port.to_s.inspect)}\s}s, txt
    end
    err.truncate 0
    err.rewind
    c = TCPSocket.new(host, port)
    c.write("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
    assert_match %r{\r\nOK\n\z}s, c.read
    txt = File.read(err.path)
    assert_match %r{\srack\.url_scheme=#{Regexp.escape('http'.inspect)}\s}s,
                 txt
    assert_match %r{\sSERVER_NAME=#{Regexp.escape('example.com'.inspect)}\s}s,
                txt
    assert_match %r{\sSERVER_PORT=#{Regexp.escape('80'.inspect)}\s}s, txt
  ensure
    c.close if c
    quit_wait(pid)
  end
end
