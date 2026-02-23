# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# this represents a Yahns::Queue before its vivified.  This only
# lives in the parent process and should be clobbered after qc_vivify
class Yahns::QueueEgg # :nodoc:
  attr_accessor :max_events, :worker_threads

  def initialize
    @max_events = 1 # 1 is good if worker_threads > 1
    @worker_threads = 7 # any default is wrong for most apps...
  end

  # only call after forking
  def vivify(fdmap)
    queue = Yahns::Queue.new
    queue.fdmap = fdmap
    queue
  end
end
