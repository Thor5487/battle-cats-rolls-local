# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPLv2 or later (https://www.gnu.org/licenses/gpl-2.0.txt)
# frozen_string_literal: true
require 'tmpdir'

# some versions of Ruby had a broken Tempfile which didn't work
# well with unlinked files.  This one is much shorter, easier
# to understand, and slightly faster (no delegation).
class Yahns::TmpIO < File # :nodoc:
  include Kgio::PipeMethods

  # creates and returns a new File object.  The File is unlinked
  # immediately, switched to binary mode, and userspace output
  # buffering is disabled
  def self.new(dir)
    retried = false
    begin
      fp = super("#{dir || Dir.tmpdir}/#{rand}", RDWR|CREAT|EXCL|APPEND, 0600)
    rescue Errno::EEXIST
      retry
    rescue Errno::EMFILE, Errno::ENFILE
      raise if retried
      retried = true
      Thread.current[:yahns_fdmap].desperate_expire(5)
      sleep(1)
      retry
    end
    unlink(fp.path)
    fp.binmode
    fp.sync = true
    fp
  end

  # pretend we're Tempfile for Rack::TempfileReaper
  alias close! close
end
