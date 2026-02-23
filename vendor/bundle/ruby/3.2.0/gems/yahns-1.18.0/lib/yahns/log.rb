# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# logging-related utility functions for all of yahns
module Yahns::Log # :nodoc:
  def self.exception(logger, prefix, exc)
    message = exc.message
    message = message.dump if /[[:cntrl:]]/ =~ message # prevent code injection
    logger.error "#{prefix}: #{message} (#{exc.class})"
    exc.backtrace.each { |line| logger.error(line) }
  end

  def self.is_log?(fp)
    append_flags = IO::WRONLY | IO::APPEND

    ! fp.closed? &&
      fp.stat.file? &&
      fp.sync &&
      (fp.fcntl(Fcntl::F_GETFL) & append_flags) == append_flags
  rescue IOError, Errno::EBADF
    false
  end

  def self.chown_all(uid, gid)
    ObjectSpace.each_object(File) do |fp|
      fp.chown(uid, gid) if is_log?(fp)
    end
  end

  # This reopens ALL logfiles in the process that have been rotated
  # using logrotate(8) (without copytruncate) or similar tools.
  # A +File+ object is considered for reopening if it is:
  #   1) opened with the O_APPEND and O_WRONLY flags
  #   2) the current open file handle does not match its original open path
  #   3) unbuffered (as far as userspace buffering goes, not O_SYNC)
  # Returns the number of files reopened
  def self.reopen_all
    to_reopen = []
    nr = 0
    ObjectSpace.each_object(File) { |fp| is_log?(fp) and to_reopen << fp }

    to_reopen.each do |fp|
      begin
        orig_st = fp.stat
      rescue IOError, Errno::EBADF # race
        next
      end

      begin
        b = File.stat(fp.path)
        next if orig_st.ino == b.ino && orig_st.dev == b.dev
      rescue Errno::ENOENT
      end

      begin
        # stdin, stdout, stderr are special.  The following dance should
        # guarantee there is no window where `fp' is unwritable in MRI
        # (or any correct Ruby implementation).
        #
        # Fwiw, GVL has zero bearing here.  This is tricky because of
        # the unavoidable existence of stdio FILE * pointers for
        # std{in,out,err} in all programs which may use the standard C library
        if fp.fileno <= 2
          # We do not want to hit fclose(3)->dup(2) window for std{in,out,err}
          # MRI will use freopen(3) here internally on std{in,out,err}
          fp.reopen(fp.path, "a")
        else
          # We should not need this: https://bugs.ruby-lang.org/issues/9036
          # MRI will not call call fclose(3) or freopen(3) here
          # since there's no associated std{in,out,err} FILE * pointer
          # This should atomically use dup3(2) (or dup2(2)) syscall
          File.open(fp.path, "a") { |tmpfp| fp.reopen(tmpfp) }
        end

        fp.sync = true
        fp.flush # IO#sync=true may not implicitly flush
        new_st = fp.stat

        # this should only happen in the master:
        if orig_st.uid != new_st.uid || orig_st.gid != new_st.gid
          fp.chown(orig_st.uid, orig_st.gid)
        end

        nr += 1
      rescue IOError, Errno::EBADF
        # not much we can do...
      end
    end
    nr
  end
end
