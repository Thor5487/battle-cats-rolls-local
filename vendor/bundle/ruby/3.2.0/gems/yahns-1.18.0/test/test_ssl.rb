# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'openssl'
class TestSSL < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper

  r, w = IO.pipe
  FAST_NB = begin
    :wait_readable == r.read_nonblock(1, exception: false)
  rescue
    false
  end
  r.close
  w.close

  # copied from test/openssl/utils.rb in Ruby:

  TEST_KEY_DH1024 = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
-----END DH PARAMETERS-----
  _end_of_pem_

  def setup
    unless FAST_NB
      skip "missing exception-free non-blocking IO in " \
           "#{RUBY_ENGINE} #{RUBY_VERSION}"
    end
    server_helper_setup
  end

  def teardown
    server_helper_teardown
  end

  def ssl_client(host, port)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.ciphers = "ADH"
    ctx.security_level = 0
    s = TCPSocket.new(host, port)
    ssl = OpenSSL::SSL::SSLSocket.new(s, ctx)
    ssl.connect
    ssl.sync_close = true
    ssl
  end

  def srv_ctx
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.ciphers = "ADH"
    ctx.security_level = 0
    ctx.tmp_dh_callback = proc { TEST_KEY_DH1024 }
    ctx
  end

  def test_ssl_basic
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    insecure = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    ctx = srv_ctx
    raw = File.read(__FILE__)
    pid = mkserver(cfg) do
      ENV["YAHNS_FD"] += ",#{insecure.fileno.to_s}"
      cfg.instance_eval do
        ru = lambda do |env|
          case path_info = env['PATH_INFO']
          when '/rack.url_scheme', '/HTTPS', '/SERVER_PORT'
            s = env[path_info[1..-1]] # remove leading slash
            s = s.inspect if s.nil?
            [ 200, {
                'Content-Length' => s.bytesize.to_s,
                'Content-Type'=>'text/plain',
              }, [ s ] ]
          when '/static'
            f = File.open(__FILE__)
            [ 200, {
                'Content-Length' => f.size.to_s,
                'Content-Type'=>'text/plain',
              },
              f ]
          else
            [ 200, {'Content-Length'=>'2'}, ['HI'] ]
          end
        end
        app(:rack, ru) {
          listen "#{host}:#{port}", ssl_ctx: ctx
          listen "#{insecure.addr[3]}:#{insecure.addr[1]}"
        }
        logger(Logger.new(err.path))
      end
    end
    client = ssl_client(host, port)
    buf = ''.dup
    { '/' => 'HI',
      '/rack.url_scheme' => 'https',
      '/HTTPS' => 'on',
      '/SERVER_PORT' => '443',
    }.each do |path, exp|
      client.write("GET #{path} HTTP/1.1\r\nHost: example.com\r\n\r\n")
      buf.clear
      re = /#{Regexp.escape(exp)}\z/
      Timeout.timeout(60) do
        buf << client.readpartial(111) until buf =~ re
      end
      head, body = buf.split("\r\n\r\n", 2)
      assert_equal exp, body
      assert_match %r{\AHTTP/1\.\d 200 OK\r\n}, head
    end

    # use port in Host: header (implemented by unicorn_http parser)
    exp = '666'
    client.write("GET /SERVER_PORT HTTP/1.1\r\nHost: example.com:#{exp}\r\n\r\n")
    re = /#{Regexp.escape(exp)}\z/
    buf.clear
    Timeout.timeout(60) do
      buf << client.readpartial(111) until buf =~ re
    end
    head, body = buf.split("\r\n\r\n", 2)
    assert_equal exp, body
    assert_match %r{\AHTTP/1\.\d 200 OK\r\n}, head

    Net::HTTP.start(insecure.addr[3], insecure.addr[1]) do |h|
      res = h.get('/rack.url_scheme')
      assert_equal 'http', res.body
      res = h.get('/HTTPS')
      assert_equal 'nil', res.body
      res = h.get('/SERVER_PORT')
      assert_equal insecure.addr[1].to_s, res.body
    end

    # read static file
    client.write("GET /static HTTP/1.1\r\nHost: example.com\r\n\r\n")
    buf.clear
    Timeout.timeout(60) do
      buf << client.readpartial(8192) until buf.include?(raw)
    end
    head, body = buf.split("\r\n\r\n", 2)
    assert_match %r{\AHTTP/1\.\d 200 OK\r\n}, head
    assert_equal raw, body

    client.write("GET / HTTP/1.0\r\n\r\n")
    head, body = client.read.split("\r\n\r\n", 2)
    assert_equal "HI", body
    assert_match %r{\AHTTP/1\.\d 200 OK\r\n}, head
  ensure
    insecure.close if insecure
    client.close if client
    quit_wait(pid)
  end

  def test_ssl_hijack
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    ctx = srv_ctx
    pid = mkserver(cfg) do
      cfg.instance_eval do
        ru = lambda do |env|
          io = env['rack.hijack'].call
          Thread.new(io) do |s|
            s.write "HTTP/1.1 201 Switching Protocols\r\n\r\n"
            case req = s.gets
            when "inspect\n"
              s.puts(s.instance_variable_get(:@ssl).inspect)
            when "remote_address\n"
              s.puts(s.remote_address.inspect)
            when "each\n"
              line = ''.dup
              s.each do |l|
                l.strip!
                line << l
                break if l == 'd'
              end
              s.puts line
            when "missing\n"
              begin
                s.any_old_invalid_test_method
                s.puts "FAIL"
              rescue => e
                s.puts "#{e.class}: #{e.message}"
              end
            when nil
              s.close
            else
              p [ :ERR, req ]
            end until s.closed?
          end
          [ 200, DieIfUsed.new, DieIfUsed.new ]
        end
        app(:rack, ru) { listen "#{host}:#{port}", ssl_ctx: ctx }
        logger(Logger.new(err.path))
        stderr_path err.path
      end
    end
    client = ssl_client(host, port)
    client.write("GET / HTTP/1.0\r\n\r\n")

    Timeout.timeout(60) do
      assert_equal "HTTP/1.1 201 Switching Protocols\r\n", client.gets
      assert_equal "\r\n", client.gets
      client.puts "inspect"
      assert_match %r{SSLSocket}, client.gets
      client.puts "remote_address"
      assert_equal client.to_io.local_address.inspect, client.gets.strip
      client.puts "missing"
      assert_match %r{NoMethodError}, client.gets

      client.puts "each"
      %w(a b c d).each { |x| client.puts(x) }
      assert_equal "abcd", client.gets.strip
    end
    errs = File.readlines(err.path).grep(/DieIfUsed/)
    assert_equal([ "INFO #{pid} closed DieIfUsed 1\n" ], errs)
  ensure
    client.close if client
    quit_wait(pid)
  end
end if defined?(OpenSSL)
