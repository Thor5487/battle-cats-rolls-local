# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'
require 'timeout'

class TestStreamFile < Testcase
  ENV["N"].to_i > 1 and parallelize_me!
  DevFD = Struct.new(:to_path)

  def test_stream_file
    fp = File.open("COPYING")
    sf = Yahns::StreamFile.new(fp, true, 0, fp.size)
    refute sf.respond_to?(:close)
    sf.wbuf_close(nil)
    assert fp.closed?
  end

  def test_fd
    fp = File.open("COPYING")
    obj = DevFD.new("/dev/fd/#{fp.fileno}")
    sf = Yahns::StreamFile.new(obj, true, 0, fp.size)
    io = sf.instance_variable_get :@tmpio
    assert_instance_of IO, io.to_io
    assert_equal fp.fileno, io.fileno
    refute sf.respond_to?(:close)
    sf.wbuf_close(nil)
    refute fp.closed?
    refute io.closed?
  end
end
