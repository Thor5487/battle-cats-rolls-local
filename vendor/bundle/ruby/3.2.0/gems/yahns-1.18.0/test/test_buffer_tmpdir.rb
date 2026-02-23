# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'sleepy_penguin'

class TestBufferTmpdir < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  attr_reader :ino, :tmpdir

  def setup
    @ino = nil
    begin
      @ino = SleepyPenguin::Inotify.new(:CLOEXEC)
    rescue
      skip "test needs inotify"
    end
    @tmpdir = yahns_mktmpdir
    server_helper_setup
  end

  def teardown
    return unless @ino
    server_helper_teardown
    @ino.close
    FileUtils.rm_rf @tmpdir
  end

  class GiantBody
    # just spew until the client gives up
    def each
      nr = 16384
      buf = "#{nr.to_s(16)}\r\n#{("!" * nr)}\r\n"
      loop do
        yield buf
      end
    end
  end

  def test_output_buffer_tmpdir
    opts = { tmpdir: @tmpdir }
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        ru = lambda { |e|
          h = {
            "Transfer-Encoding" => "chunked",
            "Content-Type" => "text/plain"
          }
          [ 200, h, GiantBody.new ]
        }
        app(:rack, ru) do
          listen "#{host}:#{port}"
          output_buffering true, opts
        end
        stderr_path err.path
      end
    end
    @ino.add_watch @tmpdir, [:CREATE, :DELETE]
    c = get_tcp_client(host, port)
    c.write "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    Timeout.timeout(30) do
      event = @ino.take
      assert_equal [:CREATE], event.events
      name = event.name
      event = @ino.take
      assert_equal [:DELETE], event.events
      assert_equal name, event.name
      refute File.exist?("#@tmpdir/#{name}")
    end
  ensure
    c.close if c
    quit_wait(pid)
  end

  def test_input_buffer_lazy; input_buffer(:lazy); end
  def test_input_buffer_true; input_buffer(true); end

  def input_buffer(btype)
    opts = { tmpdir: @tmpdir }
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    pid = mkserver(cfg) do
      cfg.instance_eval do
        require 'rack/lobster'
        app(:rack, Rack::Lobster.new) do
          listen "#{host}:#{port}"
          input_buffering btype, opts
        end
        stderr_path err.path
      end
    end
    @ino.add_watch tmpdir, [:CREATE, :DELETE]
    c = get_tcp_client(host, port)
    nr = 16384 # must be > client_body_buffer_size
    c.write "POST / HTTP/1.0\r\nContent-Length: #{nr}\r\n\r\n"
    Timeout.timeout(30) do
      event = ino.take
      assert_equal [:CREATE], event.events
      name = event.name
      event = ino.take
      assert_equal [:DELETE], event.events
      assert_equal name, event.name
      refute File.exist?("#{tmpdir}/#{name}")
    end
  ensure
    c.close if c
    quit_wait(pid)
  end
end
