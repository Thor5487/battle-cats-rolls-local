# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

require 'sleepy_penguin'

# add this as a level-triggered to any thread pool stuck on epoll_wait
# and watch it die!
if SleepyPenguin.const_defined?(:EventFD)
  class Yahns::QueueQuitter < Yahns::Sigevent # :nodoc:
    def yahns_step
      Thread.current.exit
    end
  end
else
  require_relative 'queue_quitter_pipe'
end
