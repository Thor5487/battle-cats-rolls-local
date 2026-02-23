# Copyright (C) 2015-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
begin
  require 'kcar'
  require 'yahns/proxy_pass'
rescue LoadError
end
require 'digest/md5'
class TestProxyPassNoBuffering < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  STR4 = 'abcd' * (256 * 1024)
  NCHUNK = 50
  class ProxiedApp
    def call(env)
      case env['REQUEST_METHOD']
      when 'GET'
        case env['PATH_INFO']
        when '/giant-body'
          h = [ %W(content-type text/pain) ]

          # HTTP/1.0 is not Rack-compliant, so no Rack::Lint for us :)
          if env['HTTP_VERSION'] == 'HTTP/1.1'
            h << %W(content-length #{NCHUNK * STR4.size})
          end

          body = Object.new
          def body.each
            NCHUNK.times { yield STR4 }
          end
          [ 200, h, body ]
        end
      end
    end
  end

  def setup
    @srv2 = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    server_helper_setup
    skip "kcar missing yahns/proxy_pass" unless defined?(Kcar)
    @tmpdir = yahns_mktmpdir
  end

  def teardown
    @srv2.close if defined?(@srv2) && !@srv2.closed?
    server_helper_teardown
    FileUtils.rm_rf(@tmpdir) if defined?(@tmpdir)
  end

  def check_headers(io)
    l = io.gets
    assert_match %r{\AHTTP/1\.[01] 200\b}, l
    begin
      l = io.gets
    end until l == "\r\n"
  end

  def test_proxy_pass_no_buffering
    to_close = []
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    host2, port2 = @srv2.addr[3], @srv2.addr[1]
    pxp = Yahns::ProxyPass.new("http://#{host2}:#{port2}",
                               proxy_buffering: false)
    tmpdir = @tmpdir
    pid = mkserver(cfg) do
      ObjectSpace.each_object(Yahns::TmpIO) { |io| io.close unless io.closed? }
      @srv2.close
      cfg.instance_eval do
        app(:rack, pxp) do
          listen "#{host}:#{port}"
          output_buffering true, tmpdir: tmpdir
        end
        stderr_path err.path
      end
    end

    pid2 = mkserver(cfg, @srv2) do
      ObjectSpace.each_object(Yahns::TmpIO) { |io| io.close unless io.closed? }
      @srv.close
      cfg.instance_eval do
        app(:rack, ProxiedApp.new) do
          output_buffering false
          listen "#{host2}:#{port2}"
        end
        stderr_path err.path
      end
    end
    %w(1.0 1.1).each do |ver|
      s = TCPSocket.new(host, port)
      to_close << s
      req = "GET /giant-body HTTP/#{ver}\r\nHost: example.com\r\n".dup
      req << "Connection: close\r\n" if ver == '1.1'
      req << "\r\n"
      s.write(req)
      bufs = []
      sleep 1
      10.times do
        sleep 0.1
        # ensure no files get created
        if RUBY_PLATFORM =~ /\blinux\b/ && `which lsof 2>/dev/null`.size >= 4
          qtmpdir = Regexp.quote("#@tmpdir/")
          deleted1 = `lsof -p #{pid}`.split("\n")
          deleted1 = deleted1.grep(/\bREG\b.*#{qtmpdir}.* \(deleted\)/)
          deleted2 = `lsof -p #{pid2}`.split("\n")
          deleted2 = deleted2.grep(/\bREG\b.*#{qtmpdir}.* \(deleted\)/)
          [ deleted1, deleted2 ].each do |ary|
            ary.delete_if { |x| x =~ /\.(?:err|out|rb|ru) \(deleted\)/ }
          end
          assert_equal 0, deleted1.size, "pid1=#{deleted1.inspect}"
          assert_equal 0, deleted2.size, "pid2=#{deleted2.inspect}"
          bufs.push(deleted1[0])
        end
      end
      before = bufs.size
      bufs.uniq!
      assert bufs.size < before, 'unlinked buffer should not grow'
      buf = ''.dup
      slow = Digest::MD5.new
      ft = Thread.new do
        fast = Digest::MD5.new
        f = TCPSocket.new(host2, port2)
        f.write(req)
        b2 = ''.dup
        check_headers(f)
        nf = 0
        begin
          f.readpartial(1024 * 1024, b2)
          nf += b2.bytesize
          fast.update(b2)
        rescue EOFError
          f = f.close
        end while f
        b2.clear
        [ nf, fast.hexdigest ]
      end
      Thread.abort_on_exception = true
      check_headers(s)
      n = 0
      begin
        s.readpartial(1024 * 1024, buf)
        slow.update(buf)
        n += buf.bytesize
        sleep 0.01
      rescue EOFError
        s = s.close
      end while s
      ft.join(5)
      assert_equal [n, slow.hexdigest ], ft.value

      fast = Digest::MD5.new
      f = TCPSocket.new(host, port)
      f.write(req)
      check_headers(f)
      begin
        f.readpartial(1024 * 1024, buf)
        fast.update(buf)
      rescue EOFError
        f = f.close
      end while f
      buf.clear
      assert_equal slow.hexdigest, fast.hexdigest
    end
  ensure
    to_close.each { |io| io.close unless io.closed? }
    quit_wait(pid)
    quit_wait(pid2)
  end
end
