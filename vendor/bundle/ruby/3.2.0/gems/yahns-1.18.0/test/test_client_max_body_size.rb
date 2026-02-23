# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestClientMaxBodySize < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown
  DEFMBS = 1024 * 1024

  DRAINER = lambda do |e|
    input = e["rack.input"]
    buf = ''.dup
    nr = 0
    while rv = input.read(16384, buf)
      nr += rv.size
    end
    body = nr.to_s
    h = { "Content-Length" => body.size.to_s, "Content-Type" => 'text/plain' }
    [ 200, h, [body] ]
  end

  def identity_req(bytes, body = true)
    body_bytes = body ? bytes : 0
    "PUT / HTTP/1.1\r\nConnection: close\r\nHost: example.com\r\n" \
    "Content-Length: #{bytes}\r\n\r\n#{'*' * body_bytes}"
  end

  def test_0_lazy; cmbs_test_0(:lazy); end
  def test_0_true; cmbs_test_0(true); end
  def test_0_false; cmbs_test_0(false); end

  def cmbs_test_0(btype)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize {
        app(:rack, DRAINER) {
          listen "#{host}:#{port}"
          input_buffering btype
          client_max_body_size 0
        }
      }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    default_identity_checks(host, port, 0)
    default_chunked_checks(host, port, 0)
  ensure
    quit_wait(pid)
  end

  def test_cmbs_lazy; cmbs_test(:lazy); end
  def test_cmbs_true; cmbs_test(true); end
  def test_cmbs_false; cmbs_test(false); end

  def cmbs_test(btype)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize {
        app(:rack, DRAINER) {
          listen "#{host}:#{port}"
          input_buffering btype
        }
      }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)
    default_identity_checks(host, port)
    default_chunked_checks(host, port)
  ensure
    quit_wait(pid)
  end

  def test_inf_false; big_test(false); end
  def test_inf_true; big_test(true); end
  def test_inf_lazy; big_test(:lazy); end

  def big_test(btype)
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize {
        app(:rack, DRAINER) {
          listen "#{host}:#{port}"
          input_buffering btype
          client_max_body_size nil
        }
      }
      logger(Logger.new(err.path))
    end
    pid = mkserver(cfg)

    bytes = 10 * 1024 * 1024
    r = `dd if=/dev/zero bs=#{bytes} count=1 2>/dev/null | \
         curl -sSf -HExpect: -T- http://#{host}:#{port}/`
    assert $?.success?, $?.inspect
    assert_equal bytes.to_s, r

    r = `dd if=/dev/zero bs=#{bytes} count=1 2>/dev/null | \
         curl -sSf -HExpect: -HContent-Length:#{bytes} -HTransfer-Encoding: \
         -T- http://#{host}:#{port}/`
    assert $?.success?, $?.inspect
    assert_equal bytes.to_s, r
  ensure
    quit_wait(pid)
  end

  def default_chunked_checks(host, port, defmax = DEFMBS)
    r = `curl -sSf -HExpect: -T- </dev/null http://#{host}:#{port}/`
    assert $?.success?, $?.inspect
    assert_equal "0", r

    r = `dd if=/dev/zero bs=#{defmax} count=1 2>/dev/null | \
         curl -sSf -HExpect: -T- http://#{host}:#{port}/`
    assert $?.success?, $?.inspect
    assert_equal "#{defmax}", r

    r = `dd if=/dev/zero bs=#{defmax + 1} count=1 2>/dev/null | \
         curl -sf -HExpect: -T- --write-out %{http_code} \
         http://#{host}:#{port}/ 2>&1`
    refute $?.success?, $?.inspect
    assert_equal "413", r
  end

  def default_identity_checks(host, port, defmax = DEFMBS)
    if defmax >= 666
      c = get_tcp_client(host, port)
      c.write(identity_req(666))
      assert_equal "666", c.read.split(/\r\n\r\n/)[1]
      c.close
    end

    c = get_tcp_client(host, port)
    c.write(identity_req(0))
    assert_equal "0", c.read.split(/\r\n\r\n/)[1]
    c.close

    c = get_tcp_client(host, port)
    c.write(identity_req(defmax))
    assert_equal "#{defmax}", c.read.split(/\r\n\r\n/)[1]
    c.close

    toobig = defmax + 1
    c = get_tcp_client(host, port)
    c.write(identity_req(toobig, false))
    assert_match(%r{\AHTTP/1\.[01] 413 }, Timeout.timeout(10) { c.read })
    c.close
  end
end
