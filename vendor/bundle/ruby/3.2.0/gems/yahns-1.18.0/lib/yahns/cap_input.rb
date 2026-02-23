# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPLv2 or later (https://www.gnu.org/licenses/gpl-2.0.txt)
# frozen_string_literal: true

# This is used as the @input/env["rack.input"] when
# input_buffering == true or :lazy
class Yahns::CapInput < Yahns::TmpIO # :nodoc:
  attr_writer :bytes_left

  def self.new(limit, tmpdir)
    rv = super(tmpdir)
    rv.bytes_left = limit
    rv
  end

  def write(buf)
    if (@bytes_left -= buf.size) < 0
      raise Unicorn::RequestEntityTooLargeError, "chunked body too big", []
    end
    super(buf)
  end
end
