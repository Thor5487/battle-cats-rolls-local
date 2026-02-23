# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
class Yahns::Sigevent < SleepyPenguin::EventFD # :nodoc:
  def self.new
    super(0, :CLOEXEC)
  end

  def sev_signal
    incr(1, true) # eventfd_write
  end

  def yahns_step
    value(true) # eventfd_read, we ignore this data
    :wait_readable
  end
end
