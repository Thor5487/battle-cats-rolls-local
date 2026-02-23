# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
#
# POSIX pipe version, see queue_quitter.rb for the (preferred) eventfd one
class Yahns::QueueQuitter # :nodoc:
  attr_reader :to_io
  def initialize
    @reader, @to_io = IO.pipe
  end

  def yahns_step
    Thread.current.exit
  end

  def fileno
    @to_io.fileno
  end

  def close
    @reader.close
    @to_io.close
  end

  def closed?
    @to_io.closed?
  end
end
