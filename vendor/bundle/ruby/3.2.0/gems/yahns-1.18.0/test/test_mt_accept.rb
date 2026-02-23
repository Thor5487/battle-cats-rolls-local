# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'rack/lobster'

class TestMtAccept < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def test_mt_accept
    skip "Linux kernel required" unless RUBY_PLATFORM =~ /linux/
    skip "/proc not mounted" unless File.directory?("/proc")
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, Rack::Lobster.new) { listen "#{host}:#{port}", threads: 1 }
      end
      stderr_path err.path
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) do |http|
      assert_equal 200, http.request(Net::HTTP::Get.new("/")).code.to_i
    end
    orig_count = Dir["/proc/#{pid}/task/*"].size
    quit_wait(pid)

    cfg = Yahns::Config.new
    cfg.instance_eval do
      GTL.synchronize do
        app(:rack, Rack::Lobster.new) { listen "#{host}:#{port}", threads: 2 }
      end
      stderr_path err.path
    end
    pid = mkserver(cfg)
    Net::HTTP.start(host, port) do |http|
      assert_equal 200, http.request(Net::HTTP::Get.new("/")).code.to_i
    end
    Timeout.timeout(30) do
      begin
        new_count = Dir["/proc/#{pid}/task/*"].size
      end until new_count == (orig_count + 1) && sleep(0.01)
    end
  ensure
    quit_wait(pid)
  end
end
