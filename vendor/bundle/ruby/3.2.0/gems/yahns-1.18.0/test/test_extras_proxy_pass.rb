# Copyright (C) 2015-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
begin
  require 'kcar'
rescue LoadError
end

class TestExtrasProxyPass < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper

  class ProxiedApp
    def call(env)
      h = [ %w(Content-Length 3), %w(Content-Type text/plain) ]
      case env['REQUEST_METHOD']
      when 'GET'
        [ 200, h, [ "hi\n"] ]
      when 'HEAD'
        [ 200, h, [] ]
      when 'PUT'
        buf = env['rack.input'].read
        [ 201, {
          'Content-Length' => buf.bytesize.to_s,
          'Content-Type' => 'text/plain',
          }, [ buf ] ]
      end
    end
  end

  def setup
    @srv2 = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    server_helper_setup
    skip "kcar missing for extras/proxy_pass" unless defined?(Kcar)
  end

  def teardown
    @srv2.close if defined?(@srv2) && !@srv2.closed?
    server_helper_teardown
  end

  def test_proxy_pass
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    host2, port2 = @srv2.addr[3], @srv2.addr[1]
    pid = mkserver(cfg) do
      $LOAD_PATH.unshift "#{Dir.pwd}/extras"
      olderr = $stderr
      $stderr = StringIO.new
      require 'proxy_pass'
      $stderr = olderr
      @srv2.close
      cfg.instance_eval do
        app(:rack, ProxyPass.new("http://#{host2}:#{port2}/")) do
          listen "#{host}:#{port}"
        end
        stderr_path err.path
      end
    end

    pid2 = mkserver(cfg, @srv2) do
      @srv.close
      cfg.instance_eval do
        app(:rack, ProxiedApp.new) do
          listen "#{host2}:#{port2}"
        end
        stderr_path err.path
      end
    end

    gplv3 = File.open('COPYING')

    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new('/'))
      assert_equal 200, res.code.to_i
      n = res.body.bytesize
      assert_operator n, :>, 1
      res = http.request(Net::HTTP::Head.new('/'))
      assert_equal 200, res.code.to_i
      assert_equal n, res['Content-Length'].to_i
      assert_nil res.body

      # chunked encoding
      req = Net::HTTP::Put.new('/')
      req.body_stream = gplv3
      req.content_type = 'application/octet-stream'
      req['Transfer-Encoding'] = 'chunked'
      res = http.request(req)
      gplv3.rewind
      assert_equal gplv3.read, res.body
      assert_equal 201, res.code.to_i

      # normal content-length
      gplv3.rewind
      req = Net::HTTP::Put.new('/')
      req.body_stream = gplv3
      req.content_type = 'application/octet-stream'
      req.content_length = gplv3.size
      res = http.request(req)
      gplv3.rewind
      assert_equal gplv3.read, res.body
      assert_equal 201, res.code.to_i
    end
  ensure
    gplv3.close if gplv3
    quit_wait pid
    quit_wait pid2
  end
end
