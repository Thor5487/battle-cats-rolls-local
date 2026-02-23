# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
if SleepyPenguin.const_defined?(:EventFD)
  require_relative 'sigevent_efd'
else
  require_relative 'sigevent_pipe'
end
