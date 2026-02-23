# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
if SleepyPenguin.const_defined?(:Epoll)
  require_relative 'queue_epoll'
else
  require_relative 'queue_kqueue'
end
