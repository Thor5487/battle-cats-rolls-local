# Copyright (C) 2015-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'server_helper'
require 'json'
require 'digest'
begin
  require 'kcar'
  require 'yahns/proxy_pass'
rescue LoadError
end

class TestProxyPass < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  include ServerHelper
  OMFG = 'a' * (1024 * 1024 * 32)
  TRUNCATE_BODY = "HTTP/1.1 200 OK\r\n" \
                  "Content-Length: 7\r\n" \
                  "Content-Type: text/PAIN\r\n\r\nshort".freeze
  TRUNCATE_HEAD = "HTTP/1.1 200 OK\r\n" \
                  "Content-Length: 666\r\n".freeze

  # not too big, or kcar will reject
  BIG_HEADER = [%w(Content-Type text/plain), %W(Content-Length #{OMFG.size})]
  3000.times { |i| BIG_HEADER << %W(X-#{i} BIG-HEADER!!!!!!!!!!!!!!) }
  BIG_HEADER.freeze
  STR4 = 'abcd' * (256 * 1024)
  NCHUNK = 50

  class ProxiedApp
    def call(env)
      h = [ %w(Content-Length 3), %w(Content-Type text/plain) ]
      case env['REQUEST_METHOD']
      when 'GET'
        case env['PATH_INFO']
        when '/giant-body'
          h = [ %W(Content-Length #{OMFG.size}), %w(Content-Type text/plain) ]
          [ 200, h, [ OMFG ] ]
        when '/giant-chunky-body'
          h = [ %w(content-type text/pain), %w(transfer-encoding chunked) ]
          chunky = Object.new
          def chunky.each
            head = STR4.size.to_s(16) << "\r\n"
            NCHUNK.times do
              yield head
              yield STR4
              yield "\r\n".freeze
            end
            yield "0\r\n\r\n"
          end
          [ 200, h, chunky ]
        when '/big-headers'
          [ 200, BIG_HEADER, [ OMFG ] ]
        when '/oversize-headers'
          100000.times { |x| h << %W(X-TOOBIG-#{x} #{x}) }
          [ 200, h, [ "big" ] ]
        when %r{\A/slow-headers-(\d+(?:\.\d+)?)\z}
          delay = $1.to_f
          io = env['rack.hijack'].call
          [ "HTTP/1.1 200 OK\r\n",
            "Content-Length: 7\r\n",
            "Content-Type: text/PAIN\r\n",
            "connection: close\r\n\r\n",
            "HIHIHI!"
          ].each do |l|
            io.write(l)
            sleep delay
          end
          io.close
        when '/truncate-body'
          io = env['rack.hijack'].call
          io.write(TRUNCATE_BODY)
          io.close
        when '/eof-body-fast'
          io = env['rack.hijack'].call
          io.write("HTTP/1.0 200 OK\r\n\r\neof-body-fast")
          io.close
        when '/eof-body-slow'
          io = env['rack.hijack'].call
          io.write("HTTP/1.0 200 OK\r\n\r\n")
          sleep 0.1
          io.write("eof-body-slow")
          io.close
        when '/truncate-head'
          io = env['rack.hijack'].call
          io.write(TRUNCATE_HEAD)
          io.close
        when '/response-trailer'
          h = [
            %w(Content-Type text/pain),
            %w(Transfer-Encoding chunked),
            %w(Trailer Foo)
          ]
          b = [ "3\r\n", "hi\n", "\r\n", "0\r\n", "Foo: bar", "\r\n", "\r\n" ]
          case env['HTTP_X_TRAILER']
          when 'fast'
            b = [ b.join ]
          when 'allslow'
            def b.each
              size.times do |i|
                sleep 0.1
                yield self[i]
              end
            end
          when /\Atlrslow(\d+)/
            b.instance_variable_set(:@yahns_sleep_thresh, $1.to_i)
            def b.each
              size.times do |i|
                sleep(0.1) if i > @yahns_sleep_thresh
                yield self[i]
              end
            end
          end
          [ 200, h, b ]
        when '/immediate-EOF'
          env['rack.hijack'].call.close
        when %r{\A/chunky-slow-(\d+(?:\.\d+)?)\z}
          delay = $1.to_f
          chunky = Object.new
          chunky.instance_variable_set(:@delay, delay)
          if env['HTTP_VERSION'] == 'HTTP/1.0'
            h = [ %w(Content-Type text/pain), %w(Content-Length 3) ]
            def chunky.each
              %w(H I !).each do |x|
                sleep @delay
                yield x
              end
            end
          else
            h = [ %w(Content-Type text/pain), %w(Transfer-Encoding chunked) ]
            def chunky.each
              sleep @delay
              yield "3\r\nHI!\r\n"
              sleep @delay
              yield "0\r\n\r\n"
            end
          end
          [ 200, h, chunky ]
        else
          [ 200, h, [ "hi\n"] ]
        end
      when 'HEAD'
        case env['PATH_INFO']
        when '/big-headers'
          [ 200, BIG_HEADER, [] ]
        else
          [ 200, h, [] ]
        end
      when 'PUT'
        case env['PATH_INFO']
        when '/forbidden-put'
          # ignore rack.input
          [ 403, [ %w(Content-Type text/html), %w(Content-Length 0) ], [] ]
        when '/forbidden-put-abort'
         env['rack.hijack'].call.close
         # should not be seen:
         [ 123, [ %w(Content-Type text/html), %w(Content-Length 0) ], [] ]
        when '/204'
          buf = env['rack.input'].read # drain
          [ 204, {}, [] ]
        else
          buf = env['rack.input'].read
          [ 201, {
            'Content-Length' => buf.bytesize.to_s,
            'Content-Type' => 'text/plain',
            }, [ buf ] ]
        end
      end
    end
  end

  def setup
    @srv2 = TCPServer.new(ENV["TEST_HOST"] || "127.0.0.1", 0)
    server_helper_setup
    skip "kcar missing yahns/proxy_pass" unless defined?(Kcar)
  end

  def teardown
    @srv2.close if defined?(@srv2) && !@srv2.closed?
    server_helper_teardown
  end

  def test_unix_socket_no_path
    tmpdir = yahns_mktmpdir
    unix_path = "#{tmpdir}/proxy_pass.sock"
    unix_srv = UNIXServer.new(unix_path)
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    host2, port2 = @srv2.addr[3], @srv2.addr[1]
    pid = mkserver(cfg) do
      @srv.autoclose = @srv2.autoclose = false
      ENV["YAHNS_FD"] = "#{@srv.fileno},#{@srv2.fileno}"
      cfg.instance_eval do
        app(:rack, Yahns::ProxyPass.new("unix:#{unix_path}:/$fullpath")) do
          listen "#{host}:#{port}"
        end
        app(:rack, Yahns::ProxyPass.new("unix:#{unix_path}:/foo$fullpath")) do
          listen "#{host2}:#{port2}"
        end
        stderr_path err.path
      end
    end

    pid2 = mkserver(cfg, unix_srv) do
      @srv.close
      @srv2.close
      cfg.instance_eval do
        rapp = lambda do |env|
          body = env.to_json
          hdr = {
            'Content-Length' => body.bytesize.to_s,
            'Content-Type' => 'application/json',
          }
          [ 200, hdr, [ body ] ]
        end
        app(:rack, rapp) { listen unix_path }
        stderr_path err.path
      end
    end

    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new('/f00'))
      assert_equal 200, res.code.to_i
      body = JSON.parse(res.body)
      assert_equal '/f00', body['PATH_INFO']

      res = http.request(Net::HTTP::Get.new('/f00foo'))
      assert_equal 200, res.code.to_i
      body = JSON.parse(res.body)
      assert_equal '/f00foo', body['PATH_INFO']
    end

    Net::HTTP.start(host2, port2) do |http|
      res = http.request(Net::HTTP::Get.new('/Foo'))
      assert_equal 200, res.code.to_i
      body = JSON.parse(res.body)
      assert_equal '/foo/Foo', body['PATH_INFO']

      res = http.request(Net::HTTP::Get.new('/Foofoo'))
      assert_equal 200, res.code.to_i
      body = JSON.parse(res.body)
      assert_equal '/foo/Foofoo', body['PATH_INFO']
    end
  ensure
    quit_wait(pid)
    quit_wait(pid2)
    unix_srv.close if unix_srv
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  def test_proxy_pass
    err, cfg, host, port = @err, Yahns::Config.new, @srv.addr[3], @srv.addr[1]
    host2, port2 = @srv2.addr[3], @srv2.addr[1]
    pid = mkserver(cfg) do
      @srv2.close
      cfg.instance_eval do
        app(:rack, Yahns::ProxyPass.new("http://#{host2}:#{port2}")) do
          listen "#{host}:#{port}"
          client_max_body_size nil
        end
        stderr_path err.path
      end
    end

    pid2 = mkserver(cfg, @srv2) do
      @srv.close
      cfg.instance_eval do
        app(:rack, ProxiedApp.new) do
          listen "#{host2}:#{port2}"
          client_max_body_size nil
          input_buffering :lazy
        end
        stderr_path err.path
      end
    end

    check_204_on_put(host, port)
    check_forbidden_put(host, port)
    check_eof_body(host, port)
    check_pipelining(host, port)
    check_response_trailer(host, port)

    gplv3 = File.open('COPYING')

    Net::HTTP.start(host, port) do |http|
      res = http.request(Net::HTTP::Get.new('/'))
      assert_equal 200, res.code.to_i
      n = res.body.bytesize
      assert_operator n, :>, 1
      res = http.request(Net::HTTP::Head.new('/'))
      assert_equal 200, res.code.to_i
      assert_equal n, res['Content-Length'].to_i
      assert_nil res.body

      # chunked encoding (PUT)
      req = Net::HTTP::Put.new('/')
      req.body_stream = gplv3
      req.content_type = 'application/octet-stream'
      req['Transfer-Encoding'] = 'chunked'
      res = http.request(req)
      gplv3.rewind
      assert_equal gplv3.read, res.body
      assert_equal 201, res.code.to_i

      # chunked encoding (GET)
      res = http.request(Net::HTTP::Get.new('/chunky-slow-0.1'))
      assert_equal 200, res.code.to_i
      assert_equal 'chunked', res['Transfer-encoding']
      assert_equal "HI!", res.body

      # slow headers (GET)
      res = http.request(Net::HTTP::Get.new('/slow-headers-0.01'))
      assert_equal 200, res.code.to_i
      assert_equal 'text/PAIN', res['Content-Type']
      assert_equal 'HIHIHI!', res.body

      # normal content-length (PUT)
      gplv3.rewind
      req = Net::HTTP::Put.new('/')
      req.body_stream = gplv3
      req.content_type = 'application/octet-stream'
      req.content_length = gplv3.size
      res = http.request(req)
      gplv3.rewind
      assert_equal gplv3.read, res.body
      assert_equal 201, res.code.to_i

      # giant body
      res = http.request(Net::HTTP::Get.new('/giant-body'))
      assert_equal 200, res.code.to_i
      assert_equal OMFG, res.body

      # giant chunky body
      sha1 = Digest::SHA1.new
      http.request(Net::HTTP::Get.new('/giant-chunky-body')) do |response|
        response.read_body do |chunk|
          sha1.update(chunk)
        end
      end
      check = Digest::SHA1.new
      NCHUNK.times { check.update(STR4) }
      assert_equal check.hexdigest, sha1.hexdigest

      # giant PUT content-length
      req = Net::HTTP::Put.new('/')
      req.body_stream = StringIO.new(OMFG)
      req.content_type = 'application/octet-stream'
      req.content_length = OMFG.size
      res = http.request(req)
      assert_equal OMFG, res.body
      assert_equal 201, res.code.to_i

      # giant PUT chunked encoding
      req = Net::HTTP::Put.new('/')
      req.body_stream = StringIO.new(OMFG)
      req.content_type = 'application/octet-stream'
      req['Transfer-Encoding'] = 'chunked'
      res = http.request(req)
      assert_equal OMFG, res.body
      assert_equal 201, res.code.to_i

      # sometimes upstream feeds kcar too much
      req = Net::HTTP::Get.new('/oversize-headers')
      res = http.request(req)
      errs = File.readlines(@err.path).grep(/ERROR/)
      assert_equal 1, errs.size
      assert_match %r{upstream response error:}, errs[0]
      @err.truncate(0)
    end

    # ensure we do not chunk responses back to an HTTP/1.0 client even if
    # the proxy <-> upstream connection is chunky
    %w(0 0.1).each do |delay|
      begin
        h10 = TCPSocket.new(host, port)
        h10.write "GET /chunky-slow-#{delay} HTTP/1.0\r\n\r\n"
        res = Timeout.timeout(60) { h10.read }
        assert_match %r{^Connection: close\r\n}, res
        assert_match %r{^Content-Type: text/pain\r\n}, res
        assert_match %r{\r\n\r\nHI!\z}, res
        refute_match %r{^Transfer-Encoding:}, res
        refute_match %r{\r0\r\n}, res
      ensure
        h10.close
      end
    end
    check_truncated_upstream(host, port)
    check_slow_giant_body(host, port)
    check_slow_read_headers(host, port)
  ensure
    gplv3.close if gplv3
    quit_wait pid
    quit_wait pid2
  end

  def check_pipelining(host, port)
    pl = TCPSocket.new(host, port)
    r1 = ''.dup
    r2 = ''.dup
    r3 = ''.dup
    Timeout.timeout(60) do
      pl.write "GET / HTTP/1.1\r\nHost: example.com\r\n\r\nGET /"
      until r1 =~ /hi\n/
        r1 << pl.readpartial(666)
      end

      pl.write "chunky-slow-0.1 HTTP/1.1\r\nHost: example.com\r\n\r\nP"
      until r2 =~ /\r\n3\r\nHI!\r\n0\r\n\r\n/
        r2 << pl.readpartial(666)
      end

      pl.write "UT / HTTP/1.1\r\nHost: example.com\r\n"
      pl.write "Transfer-Encoding: chunked\r\n\r\n"
      pl.write "6\r\nchunky\r\n"
      pl.write "0\r\n\r\n"

      until r3 =~ /chunky/
        r3 << pl.readpartial(666)
      end

      # ensure stuff still works after a chunked upload:
      pl.write "GET / HTTP/1.1\r\nHost: example.com\r\n\r\nP"
      after_up = ''.dup
      until after_up =~ /hi\n/
        after_up << pl.readpartial(666)
      end
      re = /^Date:[^\r\n]+/
      assert_equal after_up.sub(re, ''), r1.sub(re, '')

      # another upload, this time without chunking
      pl.write "UT / HTTP/1.1\r\nHost: example.com\r\n"
      pl.write "Content-Length: 8\r\n\r\n"
      pl.write "identity"
      identity = ''.dup

      until identity =~ /identity/
        identity << pl.readpartial(666)
      end
      assert_match %r{identity\z}, identity
      assert_match %r{\AHTTP/1\.1 201\b}, identity

      # ensure stuff still works after an identity upload:
      pl.write "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
      after_up = ''.dup
      until after_up =~ /hi\n/
        after_up << pl.readpartial(666)
      end
      re = /^Date:[^\r\n]+/
      assert_equal after_up.sub(re, ''), r1.sub(re, '')

      pl.write "GET / HTTP/1.1\r\nHost: example.com"
      sleep 0.1 # hope epoll wakes up and reads in this time
      pl.write "\r\n\r\nGET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
      burst = pl.readpartial(666)
      until burst.scan(/^hi$/).size == 2
        burst << pl.readpartial(666)
      end
      assert_equal 2, burst.scan(/^hi$/).size
      assert_match %r{\r\n\r\nhi\n\z}, burst
    end
    r1 = r1.split("\r\n").reject { |x| x =~ /^Date: / }
    r2 = r2.split("\r\n").reject { |x| x =~ /^Date: / }
    assert_equal 'HTTP/1.1 200 OK', r1[0]
    assert_equal 'HTTP/1.1 200 OK', r2[0]
    assert_match %r{\r\n\r\nchunky\z}, r3
    assert_match %r{\AHTTP/1\.1 201 Created\r\n}, r3
  rescue => e
    warn [ e.class, e.message ].inspect
    warn e.backtrace.join("\n")
  ensure
    pl.close
  end

  def check_truncated_upstream(host, port)
    # we want to make sure we show the truncated response without extra headers
    s = TCPSocket.new(host, port)
    check_err
    res = Timeout.timeout(60) do
      s.write "GET /truncate-body HTTP/1.1\r\nHost: example.com\r\n\r\n"
      s.read
    end
    s.close

    exp = "HTTP/1.1 200 OK\r\n" \
          "Content-Length: 7\r\n" \
          "Content-Type: text/PAIN\r\n" \
          "Connection: keep-alive\r\n" \
          "\r\nshort"
    assert_equal exp, res
    errs = File.readlines(@err.path).grep(/\bERROR\b/)
    assert_equal 1, errs.size
    assert_match(/upstream EOF/, errs[0])
    @err.truncate(0)

    # truncated headers or no response at all...
    # Send a 502 error
    %w(immediate-EOF truncate-head).each do |path|
      s = TCPSocket.new(host, port)
      check_err
      res = Timeout.timeout(60) do
        s.write "GET /#{path} HTTP/1.1\r\nHost: example.com\r\n\r\n"
        s.read(1024)
      end
      assert_match %r{\AHTTP/1.1 502\s+}, res
      s.close
      errs = File.readlines(@err.path).grep(/\bERROR\b/)
      assert_equal 1, errs.size
      assert_match(/upstream EOF/, errs[0])
      @err.truncate(0)
    end
  end

  def check_slow_giant_body(host, port)
    s = TCPSocket.new(host, port)
    s.write "GET /giant-body HTTP/1.0\r\n\r\n"
    sleep 0.1
    str = ''.dup
    buf = ''.dup
    assert_raises(EOFError) { loop { str << s.readpartial(400, buf) } }
    h, b = str.split(/\r\n\r\n/, 2)
    assert_equal OMFG, b
    assert_match %r{\AHTTP/1\.1 200\b}, h
  ensure
    s.close if s
  end

  def check_slow_read_headers(host, port)
    s = TCPSocket.new(host, port)
    s.write "GET /big-headers HTTP/1.1\r\nHost: example.com\r\n\r\n"
    s.write "HEAD /big-headers HTTP/1.0\r\n\r\n"
    buf = ''.dup
    res = ''.dup
    sleep 0.1
    begin
      res << s.readpartial(32786, buf)
    rescue EOFError
      break
    end while true
    # res = Timeout.timeout(60) { s.read }
    assert_match %r{\r\n\r\n\z}, res
    assert_match %r{\AHTTP/1\.1 200 OK}, res
  ensure
    s.close if s
  end

  def check_response_trailer(host, port)
    thrs = [
      "X-Trailer: fast\r\n",
      "X-Trailer: allslow\r\n",
      "X-Trailer: tlrslow1\r\n",
      "X-Trailer: tlrslow2\r\n",
      "X-Trailer: tlrslow3\r\n",
      "X-Trailer: tlrslow4\r\n",
      ''
    ].map do |x|
      Thread.new do
        s = TCPSocket.new(host, port)
        s.write "GET /response-trailer HTTP/1.1\r\n#{x}" \
                "Host: example.com\r\n\r\n"
        res = ''.dup
        buf = ''.dup
        Timeout.timeout(60) do
          until res =~ /Foo: bar\r\n\r\n\z/
            res << s.readpartial(16384, buf)
          end
        end
        assert_match(%r{\r\n0\r\nFoo: bar\r\n\r\n\z}, res)
        assert_match(%r{^Trailer: Foo\r\n}, res)
        assert_match(%r{^Transfer-Encoding: chunked\r\n}, res)
        assert_match(%r{\AHTTP/1\.1 200 OK\r\n}, res)
        s.close
        :OK
      end
    end
    thrs.each { |t| assert_equal(:OK, t.value) }
  end

  def check_eof_body(host, port)
    Timeout.timeout(30) do
      s = TCPSocket.new(host, port)
      s.write("GET /eof-body-fast HTTP/1.0\r\nConnection:keep-alive\r\n\r\n")
      res = s.read
      assert_match %r{\AHTTP/1\.[01] 200 OK\r\n}, res
      assert_match %r{\r\nConnection: close\r\n}, res
      assert_match %r{\r\n\r\neof-body-fast\z}, res
      s.close
    end

    Timeout.timeout(60) do
      s = TCPSocket.new(host, port)
      s.write("GET /eof-body-fast HTTP/1.0\r\n\r\n")
      res = s.read
      assert_match %r{\AHTTP/1\.1 200 OK\r\n}, res
      assert_match %r{\r\n\r\neof-body-fast\z}, res
      s.close

      s = TCPSocket.new(host, port)
      s.write("GET /eof-body-slow HTTP/1.0\r\n\r\n")
      res = s.read
      assert_match %r{\AHTTP/1\.1 200 OK\r\n}, res
      assert_match %r{\r\n\r\neof-body-slow\z}, res
      s.close

      # we auto-chunk on 1.1 requests and 1.0 backends
      %w(eof-body-slow eof-body-fast).each do |x|
        s = TCPSocket.new(host, port)
        s.write("GET /#{x} HTTP/1.1\r\nHost: example.com\r\n\r\n")
        res = ''.dup
        res << s.readpartial(512) until res =~ /0\r\n\r\n\z/
        s.close
        head, body = res.split("\r\n\r\n", 2)
        head = head.split("\r\n")
        assert_equal 'HTTP/1.1 200 OK', head[0]
        assert head.include?('Connection: keep-alive')
        assert head.include?('Transfer-Encoding: chunked')
        assert_match %r{\Ad\r\n#{x}\r\n0\r\n\r\n\z}, body
      end
    end
  end

  def check_forbidden_put(host, port)
    to_close = []
    Timeout.timeout(60) do
      s = TCPSocket.new(host, port)
      to_close << s
      s.write("PUT /forbidden-put HTTP/1.1\r\nHost: example.com\r\n" \
              "Content-Length: #{OMFG.size}\r\n\r\n")
      assert_equal OMFG.size, s.write(OMFG),
                   "proxy fully buffers, upstream does not"
      assert_match %r{\AHTTP/1\.1 403 }, s.readpartial(1024)
      assert_raises(EOFError) { s.readpartial(1) }

      s = TCPSocket.new(host, port)
      to_close << s
      s.write("PUT /forbidden-put-abort HTTP/1.1\r\nHost: example.com\r\n" \
              "Content-Length: #{OMFG.size}\r\n\r\n")
      assert_equal OMFG.size, s.write(OMFG),
                   "proxy fully buffers, upstream does not"
      assert_match %r{\AHTTP/1\.1 502 Bad Gateway}, s.readpartial(1024)
      assert_raises(EOFError) { s.readpartial(1) }
      @err.truncate(0)
    end
  ensure
    to_close.each(&:close)
  end

  def check_204_on_put(host, port)
    s = TCPSocket.new(host, port)
    s.write("PUT /204 HTTP/1.1\r\nHost: example.com\r\n" \
            "Content-Length: 11\r\n" \
            "Content-Type: application/octet-stream\r\n" \
            "\r\nhello worldPUT")
    buf = s.readpartial(1024)
    assert_match %r{\AHTTP/1\.1 204}, buf
    assert_match %r{\r\n\r\n\z}, buf
    refute_match %r{^Transfer-Encoding}i, buf
    refute_match %r{^Content-Length}i, buf
    assert_match %r{^Connection: keep-alive\r\n}, buf
    assert_nil IO.select([s], nil, nil, 1), 'connection persists..'

    # make sure another on the same connection works
    s.write(" / HTTP/1.1\r\nHost: example.com\r\n" \
            "Content-Length: 11\r\n" \
            "Content-Type: application/octet-stream\r\n" \
            "\r\nhello world")
    buf = s.readpartial(1024)
    assert_match %r{\r\n\r\nhello world\z}, buf
    assert_match %r{\AHTTP/1\.1 201}, buf
    assert_match(%r{^Content-Length: 11\r\n}, buf)
    assert_match %r{^Connection: keep-alive\r\n}, buf
    assert_nil IO.select([s], nil, nil, 1), 'connection persists..'
  ensure
    s.close if s
  end
end
