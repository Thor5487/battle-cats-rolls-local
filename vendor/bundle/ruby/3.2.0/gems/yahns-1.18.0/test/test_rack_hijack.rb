# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'

class TestRackHijack < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  alias setup server_helper_setup
  alias teardown server_helper_teardown

  HIJACK_APP = lambda { |env|
    case env["PATH_INFO"]
    when "/hijack_input"
      io = env["rack.hijack"].call
      env["rack.hijack_io"].write("HTTP/1.0 201 OK\r\n\r\n")
      io.write("rack.input contents: #{env['rack.input'].read}")
      io.close
      return [ 500, {}, DieIfUsed.new ]
    when "/hijack_req"
      io = env["rack.hijack"].call
      if io.respond_to?(:read_nonblock) &&
         env["rack.hijack_io"].respond_to?(:read_nonblock)

        # exercise both, since we Rack::Lint may use different objects
        env["rack.hijack_io"].write("HTTP/1.0 200 OK\r\n\r\n")
        io.write("request.hijacked")
        io.close
        return [ 500, {}, DieIfUsed.new ]
      end
      [ 500, {}, [ "hijack BAD\n" ] ]
    when "/hijack_res"
      r = "response.hijacked"
      [ 200,
        {
          "X-Test" => "zzz",
          "Content-Length" => r.bytesize.to_s,
          "rack.hijack" => proc { |x| x.write(r); x.close }
        },
        DieIfUsed.new
      ]
    end
  }

  def test_hijack
    err = @err
    cfg = Yahns::Config.new
    host, port = @srv.addr[3], @srv.addr[1]
    cfg.instance_eval do
      GTL.synchronize { app(:rack, HIJACK_APP) { listen "#{host}:#{port}" } }
      logger(Logger.new(err.path))
      stderr_path err.path
    end
    pid = mkserver(cfg)
    res = Net::HTTP.start(host, port) { |h| h.get("/hijack_req") }

    wait_for_msg = lambda do |n|
      tries = 10000
      begin
        Thread.new { Thread.pass }.join # calls sched_yield() on MRI
      end until File.readlines(err.path).grep(/DieIfUsed/).size >= n ||
                (tries -= 1) < 0
    end
    assert_equal "request.hijacked", res.body
    assert_equal 200, res.code.to_i
    assert_equal "1.0", res.http_version

    wait_for_msg.call(1)

    res = Net::HTTP.start(host, port) { |h| h.get("/hijack_res") }
    assert_equal "response.hijacked", res.body
    assert_equal 200, res.code.to_i
    assert_equal "zzz", res["X-Test"]
    assert_equal "1.1", res.http_version

    wait_for_msg.call(2)

    errs = File.readlines(err.path).grep(/DieIfUsed/)
    assert_equal([ "INFO #{pid} closed DieIfUsed 1\n",
                   "INFO #{pid} closed DieIfUsed 2\n" ], errs)

    res = Net::HTTP.start(host, port) do |h|
      hdr = { "Content-Type" => 'application/octet-stream' }
      h.put("/hijack_input", "BLAH", hdr)
    end
    assert_equal "rack.input contents: BLAH", res.body
    assert_equal 201, res.code.to_i
    assert_equal "1.0", res.http_version

    # ancient "HTTP/0.9"
    c = get_tcp_client(host, port)
    c.write("GET /hijack_res\r\n\r\n")
    res = Timeout.timeout(30) { c.read }
    assert_equal 'response.hijacked', res
  ensure
    quit_wait(pid)
  end
end
