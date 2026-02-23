# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestExpect100 < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  APP = lambda do |env|
    h = [ %w(Content-Length 0), %w(Content-Type text/plain) ]
    if env["HTTP_EXPECT"] =~ /100-continue/
      code = env["HTTP_X_FORCE_RCODE"] || 100
      [ code, h, [] ]
    else
      env["rack.input"].read
      [ 201, h, [] ]
    end
  end

  def test_buffer_noccc; _test_expect_100(true, false); end
  def test_nobuffer_noccc; _test_expect_100(false, false); end
  def test_lazybuffer_noccc; _test_expect_100(:lazy, false); end
  def test_buffer_ccc; _test_expect_100(true, true); end
  def test_nobuffer_ccc; _test_expect_100(false, true); end
  def test_lazybuffer_ccc; _test_expect_100(:lazy, true); end

  def _test_expect_100(btype, ccc)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      stderr_path err.path
      GTL.synchronize {
        app(:rack, APP) {
          listen "#{host}:#{port}"
          input_buffering btype
          check_client_connection ccc
        }
      }
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    r = "PUT / HTTP/1.0\r\nExpect: 100-continue\r\n\r\n"
    c.write(r)
    assert c.wait(10), "timed out"
    buf = c.read
    assert_match(%r{\AHTTP/1\.1 100 Continue\r\n\r\nHTTP/1\.1 201}, buf)

    rc = system("curl -sSf -T- http://#{host}:#{port}/", in: "/dev/null")
    assert $?.success?, $?.inspect
    assert rc
  ensure
    quit_wait(pid)
  end

  def _test_reject(btype, ccc)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      stderr_path err.path
      GTL.synchronize {
        app(:rack, APP) {
          listen "#{host}:#{port}"
          input_buffering btype
          check_client_connection ccc
        }
      }
    end
    pid = mkserver(cfg)
    c = get_tcp_client(host, port)
    r = "PUT / HTTP/1.0\r\nExpect: 100-continue\r\nX-Force-RCODE: 666\r\n\r\n"
    c.write(r)
    assert c.wait(10), "timed out"
    buf = c.read
    assert_match(%r{\AHTTP/1\.1 666\r\n}, buf)

    url = "http://#{host}:#{port}/"
    rc = system("curl -sf -T- -HX-Force-Rcode:666 #{url}", in: "/dev/null")
    refute $?.success?, $?.inspect
    refute rc
  ensure
    quit_wait(pid)
  end

  def test_reject_lazy_noccc; _test_reject(:lazy, false); end
  def test_reject_true_noccc; _test_reject(false, false); end
  def test_reject_lazy_ccc; _test_reject(:lazy, true); end
  def test_reject_true_ccc; _test_reject(false, true); end

  def test_swait_t_t; _swait(true, true, [1]); end
  def test_swait_f_f; _swait(false, false, [1]); end
  def test_swait_t_f; _swait(true, false, [1]); end
  def test_swait_f_t; _swait(false, true, [1]); end
  def test_swait_l_t; _swait(:lazy, true, [1]); end
  def test_swait_l_f; _swait(:lazy, false, [1]); end

  def test_swait2_t_t; _swait(true, true, [1,2]); end
  def test_swait2_f_f; _swait(false, false, [1,2]); end
  def test_swait2_t_f; _swait(true, false, [1,2]); end
  def test_swait2_f_t; _swait(false, true, [1,2]); end
  def test_swait2_l_t; _swait(:lazy, true, [1,2]); end
  def test_swait2_l_f; _swait(:lazy, false, [1,2]); end

  def test_swait3_t_t; _swait(true, true, [1,3]); end
  def test_swait3_f_f; _swait(false, false, [1,3]); end
  def test_swait3_t_f; _swait(true, false, [1,3]); end
  def test_swait3_f_t; _swait(false, true, [1,3]); end
  def test_swait3_l_t; _swait(:lazy, true, [1,3]); end
  def test_swait3_l_f; _swait(:lazy, false, [1,3]); end

  def test_swait_t_t_ccc; _swait(true, true, [1], true); end
  def test_swait_f_f_ccc; _swait(false, false, [1], true); end
  def test_swait_t_f_ccc; _swait(true, false, [1], true); end
  def test_swait_f_t_ccc; _swait(false, true, [1], true); end
  def test_swait_l_t_ccc; _swait(:lazy, true, [1], true); end
  def test_swait_l_f_ccc; _swait(:lazy, false, [1], true); end

  def test_swait2_t_t_ccc; _swait(true, true, [1,2], true); end
  def test_swait2_f_f_ccc; _swait(false, false, [1,2], true); end
  def test_swait2_t_f_ccc; _swait(true, false, [1,2], true); end
  def test_swait2_f_t_ccc; _swait(false, true, [1,2], true); end
  def test_swait2_l_t_ccc; _swait(:lazy, true, [1,2], true); end
  def test_swait2_l_f_ccc; _swait(:lazy, false, [1,2], true); end

  def test_swait3_t_t_ccc; _swait(true, true, [1,3], true); end
  def test_swait3_f_f_ccc; _swait(false, false, [1,3], true); end
  def test_swait3_t_f_ccc; _swait(true, false, [1,3], true); end
  def test_swait3_f_t_ccc; _swait(false, true, [1,3], true); end
  def test_swait3_l_t_ccc; _swait(:lazy, true, [1,3], true); end
  def test_swait3_l_f_ccc; _swait(:lazy, false, [1,3], true); end

  def test_swait3_t_t_ccc_body; _swait(true, true, [1,3], true, "HI"); end
  def test_swait3_f_f_ccc_body; _swait(false, false, [1,3], true, "HI"); end
  def test_swait3_t_f_ccc_body; _swait(true, false, [1,3], true, "HI"); end
  def test_swait3_f_t_ccc_body; _swait(false, true, [1,3], true, "HI"); end
  def test_swait3_l_t_ccc_body; _swait(:lazy, true, [1,3], true, "HI"); end
  def test_swait3_l_f_ccc_body; _swait(:lazy, false, [1,3], true, "HI"); end

  def _swait(ibtype, obtype, block_on, ccc = false, body = "")
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      stderr_path err.path
      GTL.synchronize {
        app(:rack, APP) {
         listen "#{host}:#{port}"
         output_buffering obtype
         input_buffering ibtype
         check_client_connection ccc
        }
      }
    end
    pid = mkserver(cfg) do
      $_tw_blocked = 0
      $_tw_block_on = block_on
      Yahns::HttpClient.__send__(:include, TrywriteBlocked)
    end
    c = get_tcp_client(host, port)
    if body.size > 0
      r = "PUT / HTTP/1.0\r\nExpect: 100-continue\r\n" \
          "Content-Length: #{body.size}\r\n\r\n#{body}"
    else
      r = "PUT / HTTP/1.0\r\nExpect: 100-continue\r\n\r\n"
    end
    c.write(r)
    assert c.wait(10), "timed out"
    buf = c.read
    assert_match(%r{\AHTTP/1\.1 100 Continue\r\n\r\nHTTP/1\.1 201}, buf)
  ensure
    quit_wait(pid)
  end
end
