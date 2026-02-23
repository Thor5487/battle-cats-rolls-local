# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'
require 'timeout'

class TestWbuf < Testcase
  ENV["N"].to_i > 1 and parallelize_me!

  def setup
    skip 'sendfile missing' unless IO.instance_methods.include?(:sendfile)
  end

  class KgioUS < UNIXSocket
    include Kgio::SocketMethods
    def self.output_buffer_tmpdir
      Dir.tmpdir
    end
  end

  def socketpair
    KgioUS.pair
  end

  def test_wbuf
    skip "sendfile not Linux-compatible" if RUBY_PLATFORM !~ /linux/
    buf = "*" * (16384 * 2)
    nr = 1000
    [ true, false ].each do |persist|
      wbuf = Yahns::Wbuf.new([], persist)
      assert_equal false, wbuf.busy
      a, b = socketpair
      assert_nil wbuf.wbuf_write(a, "HIHI")
      assert_equal "HIHI", b.read(4)
      nr.times { wbuf.wbuf_write(a, buf) }
      assert_equal :wait_writable, wbuf.wbuf_flush(a)
      done = cloexec_pipe
      thr = Thread.new do
        rv = []
        until rv[-1] == persist
          IO.select(nil, [a])
          tmp = wbuf.wbuf_flush(a)
          rv << tmp
        end
        done[1].syswrite '.'
        rv
      end

      wait = true
      begin
        if wait
          r = IO.select([b,done[0]], nil, nil, 5)
        end
        b.read_nonblock((rand * 1024).to_i + 666, buf)
        wait = (r[0] & done).empty?
      rescue Errno::EAGAIN
        break
      end while true

      assert_equal thr, thr.join(5)
      rv = thr.value
      assert_equal persist, rv.pop
      assert(rv.all? { |x| x == :wait_writable })
      a.close
      b.close
      done.each { |io| io.close }
    end
  end

  def test_wbuf_blocked
    a, b = socketpair
    skip "sendfile not Linux-compatible" if RUBY_PLATFORM !~ /linux/
    buf = "." * 4096
    4.times do
      begin
        a.write_nonblock(buf)
      rescue Errno::EAGAIN
        break
      end while true
    end
    wbuf = Yahns::Wbuf.new([], true)

    rv1 = wbuf.wbuf_write(a, buf)
    rv2 = wbuf.wbuf_flush(a)
    case rv1
    when nil
      assert_equal true, rv2, 'some kernels succeed with real sendfile'
    when :wait_writable
      assert_equal :wait_writable, rv2, 'some block on sendfile'
    else
      flunk "unexpected from wbuf_write/flush: #{rv1.inspect} / #{rv2.inspect}"
    end

    # drain the buffer
    Timeout.timeout(10) { b.read(b.nread) until b.nread == 0 }

    # b.nread will increase after this
    assert_nil wbuf.wbuf_write(a, "HI")
    nr = b.nread
    assert_operator nr, :>, 0
    assert_equal b, IO.select([b], nil, nil, 5)[0][0]
    b.read(nr - 2) if nr > 2
    assert_equal b, IO.select([b], nil, nil, 5)[0][0]
    assert_equal "HI", b.read(2), "read the end of the response"
    assert_equal true, wbuf.wbuf_flush(a)
  ensure
    a.close
    b.close
  end

  def test_wbuf_flush_close
    pipe = cloexec_pipe
    persist = true
    wbuf = Yahns::Wbuf.new(pipe[0], persist)
    refute wbuf.respond_to?(:close) # we don't want this for HttpResponse body
    sp = socketpair
    rv = nil

    buf = ("*" * 16384) << "\n"
    thr = Thread.new do
      1000.times { pipe[1].write(buf) }
      pipe[1].close
    end

    pipe[0].each { |chunk| rv = wbuf.wbuf_write(sp[1], chunk) }
    assert_equal thr, thr.join(5)
    assert_equal :wait_writable, rv

    done = cloexec_pipe
    thr = Thread.new do
      rv = []
      until rv[-1] == persist
        IO.select(nil, [sp[1]])
        rv << wbuf.wbuf_flush(sp[1])
      end
      done[1].syswrite '.'
      rv
    end

    wait = true
    begin
      if wait
        r = IO.select([sp[0],done[0]], nil, nil, 5)
      end
      sp[0].read_nonblock(16384, buf)
      wait = (r[0] & done).empty?
    rescue Errno::EAGAIN
      break
    end while true

    assert_equal thr, thr.join(5)
    rv = thr.value
    assert_equal true, rv.pop
    assert rv.all? { |x| x == :wait_writable }
    assert pipe[0].closed?
    sp.each(&:close)
    done.each(&:close)
  end
end
