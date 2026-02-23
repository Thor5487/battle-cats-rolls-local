# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPLv2 or later (https://www.gnu.org/licenses/gpl-2.0.txt)
# frozen_string_literal: true
class Yahns::MaxBody::RewindableWrapper < Yahns::MaxBody::Wrapper # :nodoc:
  def initialize(rack_input, limit)
    @orig_limit = limit
    super
  end

  def rewind
    @limit = @orig_limit
    @rbuf = ''.dup
    @input.rewind
  end

  def size
    @input.size
  end
end
