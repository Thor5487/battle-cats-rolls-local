# -*- encoding: binary -*-
# Copyright (C) 2009-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-2.0.txt)
# frozen_string_literal: true
require_relative 'helper'

class TestTmpIO < Testcase
  def setup
    skip 'sendfile missing' unless IO.instance_methods.include?(:sendfile)
  end

  def test_writev
    a, b = UNIXSocket.pair
    a.extend Kgio::PipeMethods
    tmpio = Yahns::TmpIO.new(Dir.tmpdir)
    ary = [ "hello\n".freeze, "world\n".freeze ].freeze
    tmpio.kgio_trywritev(ary)
    a.trysendfile(tmpio, 0, 12)
    assert_equal "hello\nworld\n", b.read(12)
  ensure
    b.close
    a.close
    tmpio.close
  end
end
