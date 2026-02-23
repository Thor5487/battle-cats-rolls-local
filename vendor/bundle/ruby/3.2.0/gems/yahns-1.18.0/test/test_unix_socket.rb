# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestUnixSocket < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  def unix_socket(path)
    Timeout.timeout(30) do
      begin
        return UNIXSocket.new(path)
      rescue Errno::ENOENT
        sleep 0.01
        retry
      end
    end
  end

  def test_socket
    tmpdir = yahns_mktmpdir
    err, cfg = @err, Yahns::Config.new
    sock = "#{tmpdir}/sock"
    cfg.instance_eval do
      ru = lambda { |_| [ 200, {'Content-Length'=>'2'}, ['HI'] ] }
      GTL.synchronize { app(:rack, ru) { listen sock } }
      stderr_path err.path
    end
    pid = mkserver(cfg)
    c = unix_socket(sock)
    c.write "GET / HTTP/1.0\r\n\r\n"
    assert_equal c, c.wait(30)
    buf = c.read
    assert_match %r{\AHTTP/1\.1 200 OK\r\n}, buf
    assert_match %r{\r\n\r\nHI\z}, buf
    st = File.stat(sock)
    assert st.world_readable?
    assert st.world_writable?
    c.close
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end

  def test_socket_perms
    tmpdir = yahns_mktmpdir
    err, cfg = @err, Yahns::Config.new
    sock = "#{tmpdir}/sock"
    cfg.instance_eval do
      ru = lambda { |_| [ 200, {'Content-Length'=>'2'}, ['HI'] ] }
      GTL.synchronize { app(:rack, ru) { listen sock, umask: 0077 } }
      stderr_path err.path
    end
    pid = mkserver(cfg)
    c = unix_socket(sock)
    c.write "GET / HTTP/1.0\r\n\r\n"
    assert_equal c, c.wait(30)
    buf = c.read
    assert_match %r{\AHTTP/1\.1 200 OK\r\n}, buf
    assert_match %r{\r\n\r\nHI\z}, buf
    st = File.stat(sock)
    refute st.world_readable?
    refute st.world_writable?
  ensure
    quit_wait(pid)
    FileUtils.rm_rf(tmpdir)
  end
end
