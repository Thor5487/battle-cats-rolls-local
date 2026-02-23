# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'zlib'
require 'time'

class TestExtrasAutoindex < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper

  def setup
    @tmpdir = yahns_mktmpdir
    server_helper_setup
    skip 'Ruby 2.x required' unless ''.respond_to?(:b)
  end

  def teardown
    server_helper_teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_autoindex
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    tmpdir = @tmpdir
    pid = mkserver(cfg) do
      $LOAD_PATH.unshift "#{Dir.pwd}/extras"
      require 'try_gzip_static'
      require 'autoindex'
      cfg.instance_eval do
        app(:rack, Autoindex.new(TryGzipStatic.new(tmpdir))) do
          listen "#{host}:#{port}"
        end
        stderr_path err.path
      end
    end

    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      File.open("#@tmpdir/foo", "w").close
      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      assert_match %r{foo}, res.body
      Dir.mkdir "#@tmpdir/bar"

      res = http.request(Net::HTTP::Get.new("/"))
      assert_equal 200, res.code.to_i
      refute_match %r{\.\./}, res.body, "top level should not link to parent"
      assert_match %r{foo}, res.body

      res = http.request(Net::HTTP::Get.new("/bar/"))
      assert_equal 200, res.code.to_i
      assert_match %r{\.\./}, res.body, "link to parent present"
    end
  ensure
    quit_wait pid
  end
end
