# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'rack'
# trigger autoload, since rack 1.x => 2.x renames:
# 'rack/commonlogger' => 'rack/common_logger'
# so we can't require directly
Rack::CommonLogger.class

class TestReopenLogs < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_reopen_logs_noworker; reopen(false); end
  def test_reopen_logs_worker; reopen(true); end

  def reopen(worker)
    err = @err
    out = tmpfile(%w(log .out))
    opath = out.path
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      stderr_path err.path
      stdout_path opath
      GTL.synchronize do
        app = Rack::Builder.new do
          use Rack::CommonLogger, $stdout
          use Rack::ContentLength
          use Rack::ContentType, "text/plain"
          run lambda { |_| [ 200, {}, [ "#$$" ] ] }
        end
        app(:rack, app.to_app) { listen "#{host}:#{port}" }
      end
      worker_processes 1 if worker
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/aaa"))
      assert_equal 200, res.code.to_i
      orig = res.body
      Timeout.timeout(10) { Thread.pass until File.read(opath) =~ /aaa/ }
      File.unlink(opath)
      Process.kill(:USR1, pid)
      Timeout.timeout(10) { sleep(0.01) until File.exist?(opath) }

      # we need to repeat the HTTP request since the worker_processes
      # may not have switched to the new file, yet.
      Timeout.timeout(10) do
        begin
          res = http.request(Net::HTTP::Get.new("/bbb"))
          assert_equal 200, res.code.to_i
          assert_equal orig, res.body
        end until File.read(opath) =~ /bbb/
      end
    end
  ensure
    quit_wait(pid)
  end
end
