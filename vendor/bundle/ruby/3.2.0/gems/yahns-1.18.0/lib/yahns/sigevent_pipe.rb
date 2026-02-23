# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
class Yahns::Sigevent # :nodoc:
  attr_reader :to_io
  def initialize
    @to_io, @wr = IO.pipe
  end

  def wait_readable(*args)
    @to_io.wait_readable(*args)
  end

  def fileno
    @to_io.fileno
  end

  def sev_signal
    @wr.write_nonblock(".", exception: false)
  end

  def yahns_step
    # 11 byte strings -> no malloc on YARV
    while String === @to_io.read_nonblock(11, exception: false)
    end
    :wait_readable
  end

  def close
    @to_io.close
    @wr.close
  end

  def closed?
    @to_io.closed?
  end
end
