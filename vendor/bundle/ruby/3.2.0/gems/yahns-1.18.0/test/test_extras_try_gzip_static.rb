# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'zlib'
require 'time'

class TestExtrasTryGzipStatic < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  GPL_TEXT = IO.binread("COPYING").freeze

  def setup
    @tmpdir = yahns_mktmpdir
    server_helper_setup
    skip 'Ruby 2.x required' unless ''.respond_to?(:b)
  end

  def teardown
    server_helper_teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_gzip_static
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    tmpdir = @tmpdir
    pid = mkserver(cfg) do
      require './extras/try_gzip_static'
      cfg.instance_eval do
        app(:rack, TryGzipStatic.new(tmpdir)) do
          listen "#{host}:#{port}"
        end
        stderr_path err.path
      end
    end

    Net::HTTP.start(host, port) do |http|
      uri = "/COPYING/foo" + ('-' * 4096)
      begin
        res = http.request(Net::HTTP::Get.new(uri))
      end while res.code.to_i == 414 && uri.chop!
      res = http.request(Net::HTTP::Get.new("/COPYING/foo"))
      assert_equal 404, res.code.to_i
      lines = File.readlines(err.path)
      File.truncate(err.path, 0)
      assert_operator lines.size, :<, 3, lines.map! { |s| s[0,64] }.inspect
    end

    begin # setup
      gpl = "#{tmpdir}/COPYING"
      File.symlink gpl, "#{tmpdir}/COPYING.abssymlink"
      File.symlink "COPYING", "#{tmpdir}/COPYING.relsymlink"
      gplgz = "#{tmpdir}/COPYING.gz"
      FileUtils.cp("COPYING", gpl)
      _, status = Process.waitpid2(xfork do
        File.open(gplgz, "w") do |fp|
          Zlib::GzipWriter.wrap(fp.dup) { |io| io.write(GPL_TEXT) }
        end
        exit!(0)
      end)
      assert status.success?, status.inspect
      st = File.stat(gpl)
      gz_st = File.stat(gplgz)
      assert_equal GPL_TEXT, `zcat #{gplgz}`, "Eric screwed up using zlib"
      File.utime(st.atime, st.mtime, gplgz)
    end

    check = lambda do |req, &blk|
      c = get_tcp_client(host, port)
      begin
        c.write "#{req}\r\n\r\n"
        buf = c.read(666000)
        head, body = buf.split(/\r\n\r\n/)
        blk.call(head)
        body
      ensure
        c.close
      end
    end

    Timeout.timeout(30) do # basic tests
      %w(GET HEAD).each do |m|
        body = check.call("#{m} /COPYING HTTP/1.0") do |head|
          refute_match %r{^Content-Encoding: gzip\b}, head
          assert_match %r{^Content-Type: text/plain\b}, head
          assert_match %r{^Content-Length: #{st.size}\b}, head
        end
        case m
        when "GET" then assert_equal GPL_TEXT, body
        when "HEAD" then assert_nil body
        end

        %w(COPYING COPYING.abssymlink COPYING.relsymlink).each do |path|
          req = "#{m} /#{path} HTTP/1.0\r\nAccept-Encoding: gzip"
          body = check.call(req) do |head|
            assert_match %r{^Content-Encoding: gzip\b}, head
            assert_match %r{^Content-Type: text/plain\b}, head
            assert_match %r{^Content-Length: #{gz_st.size}\b}, head
          end
          case m
          when "GET"
            body =StringIO.new(body)
            assert_equal GPL_TEXT, Zlib::GzipReader.new(body).read
          when "HEAD" then assert_nil body
          end
        end
      end
    end

    Timeout.timeout(30) do # range tests
      %w(HEAD GET).each do |m|
        req = "#{m} /COPYING HTTP/1.0\r\n" \
              "Range: bytes=5-46\r\nAccept-Encoding: gzip"
        body = check.call(req) do |head|
          assert_match %r{\AHTTP/1\.1 206 Partial Content\r\n}, head
          refute_match %r{^Content-Encoding: gzip\b}, head
          assert_match %r{^Content-Type: text/plain\b}, head
          assert_match %r{^Content-Length: 42\b}, head
          assert_match %r{^Content-Range: bytes 5-46/#{st.size}\r\n}, head
        end
        case m
        when "GET" then assert_equal GPL_TEXT[5..46], body
        when "HEAD" then assert_nil body
        end

        req = "#{m} /COPYING HTTP/1.0\r\n" \
              "Range: bytes=66666666-\r\nAccept-Encoding: gzip"
        check.call(req) do |head|
          assert_match %r{^Content-Range: bytes \*/#{st.size}\r\n}, head
          assert_match %r{\AHTTP/1\.1 416 }, head
        end
      end
    end

    Timeout.timeout(30) do # gzip counterpart is nonexistent
      File.link(gpl, "#{gpl}.hardlink")
      %w(GET HEAD).each do |m|
        req = "#{m} /COPYING.hardlink HTTP/1.0\r\nAccept-Encoding: gzip"
        body = check.call(req) do |head|
          refute_match %r{^Content-Encoding: gzip\b}, head
          assert_match %r{^Content-Type: text/plain\b}, head
          assert_match %r{^Content-Length: #{st.size}\b}, head
        end
        case m
        when "GET" then assert_equal GPL_TEXT, body
        when "HEAD" then assert_nil body
        end
      end
    end

    Timeout.timeout(30) do # If-Modified-Since
      %w(GET HEAD).each do |m|
        req = "#{m} /COPYING HTTP/1.0\r\n" \
              "If-Modified-Since: #{st.mtime.httpdate}"
        body = check.call(req) do |head|
          assert_match %r{\AHTTP/1\.1 304 Not Modified}, head
        end
        assert_nil body
      end
    end

    # skew the times of the gzip file, should now fail to use gzipped
    Timeout.timeout(30) do
      File.utime(Time.at(0), Time.at(0), gplgz)

      %w(GET HEAD).each do |m|
        req = "#{m} /COPYING HTTP/1.0\r\nAccept-Encoding: gzip"
        body = check.call(req) do |head|
          refute_match %r{^Content-Encoding: gzip\b}, head
          assert_match %r{^Content-Type: text/plain\b}, head
          assert_match %r{^Content-Length: #{st.size}\b}, head
        end
        case m
        when "GET" then assert_equal GPL_TEXT, body
        when "HEAD" then assert_nil body
        end
      end
    end

    Timeout.timeout(30) do # 404
      %w(GET HEAD).each do |m|
        req = "#{m} /cp-ing HTTP/1.0\r\nAccept-Encoding: gzip"
        check.call(req) do |head|
          assert_match %r{HTTP/1\.1 404 }, head
        end
      end
      check.call("FOO /COPYING HTTP/1.0") do |head|
        assert_match %r{HTTP/1\.1 405 }, head
      end
    end

    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new('/COPYING/foo'))
      assert_equal 404, res.code.to_i
    end
  ensure
    quit_wait(pid)
  end
end
