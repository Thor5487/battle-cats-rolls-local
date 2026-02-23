# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'
require 'rack/lobster'

class TestConfig < Testcase
  ENV["N"].to_i > 1 and parallelize_me!

  def test_initialize
    cfg = Yahns::Config.new
    assert_instance_of Yahns::Config, cfg
  end

  def test_multi_conf_example
    pid = xfork do
      tmpdir = yahns_mktmpdir

      # modify the example config file for testing
      path = "examples/yahns_multi.conf.rb"
      cfgs = File.read(path)
      cfgs.gsub!(%r{/path/to/}, "#{tmpdir}/")
      conf = File.open("#{tmpdir}/yahns_multi.conf.rb", "w")
      conf.sync = true
      conf.write(cfgs)
      File.open("#{tmpdir}/another.ru", "w") do |fp|
        fp.puts("run Rack::Lobster.new\n")
      end
      FileUtils.mkpath("#{tmpdir}/another")

      cfg = Yahns::Config.new(conf.path)
      FileUtils.rm_rf(tmpdir)
      exit!(Yahns::Config === cfg)
    end
    _, status = Process.waitpid2(pid)
    assert status.success?
  end

  def test_rack_basic_conf_example
    pid = xfork do
      tmpdir = yahns_mktmpdir

      # modify the example config file for testing
      path = "examples/yahns_rack_basic.conf.rb"
      cfgs = File.read(path)
      cfgs.gsub!(%r{/path/to/}, "#{tmpdir}/")
      Dir.mkdir("#{tmpdir}/my_app")
      Dir.mkdir("#{tmpdir}/my_logs")
      Dir.mkdir("#{tmpdir}/my_pids")
      conf = File.open("#{tmpdir}/yahns_rack_basic.conf.rb", "w")
      conf.sync = true
      conf.write(cfgs)
      File.open("#{tmpdir}/my_app/config.ru", "w") do |fp|
        fp.puts("run Rack::Lobster.new\n")
      end
      cfg = Yahns::Config.new(conf.path)
      FileUtils.rm_rf(tmpdir) if tmpdir
      exit!(Yahns::Config === cfg)
    end
    _, status = Process.waitpid2(pid)
    assert status.success?
  end
end
