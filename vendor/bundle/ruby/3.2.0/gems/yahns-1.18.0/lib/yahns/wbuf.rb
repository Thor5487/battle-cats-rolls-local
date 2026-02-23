# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'wbuf_common'

# This class is triggered whenever we need write buffering for clients
# reading responses slowly.  Small responses which fit into kernel socket
# buffers do not trigger this.  yahns will always attempt to write to kernel
# socket buffers first to avoid unnecessary copies in userspace.
#
# Thus, most data is into copied to the kernel only once, the kernel
# will perform zero-copy I/O from the page cache to the socket.  The
# only time data may be copied twice is the initial write()/send()
# which triggers EAGAIN.
#
# We only buffer to the filesystem (note: likely not a disk, since this
# is short-lived).  We let the sysadmin/kernel decide whether or not
# the data needs to hit disk or not.
#
# This avoids large allocations from malloc, potentially limiting
# fragmentation and keeping (common) smaller allocations fast.
# General purpose malloc implementations in the 64-bit era tend to avoid
# releasing memory back to the kernel, so large heap allocations are best
# avoided as the kernel has little chance to reclaim memory used for a
# temporary buffer.
#
# The biggest downside of this approach is it requires an FD, but yahns
# configurations are configured for many FDs anyways, so it's unlikely
# to be a scalability issue.
class Yahns::Wbuf # :nodoc:
  include Yahns::WbufCommon
  attr_reader :busy
  IO_WRITEV = RUBY_VERSION.to_r >= 2.5 # IO#write uses writev

  def initialize(body, persist)
    @tmpio = nil
    @sf_offset = @sf_count = 0
    @wbuf_persist = persist # whether or not we keep the connection alive
    @body = body # something we call #close on when done writing
    @busy = false
  end

  if IO_WRITEV
    def wbuf_writev(buf)
      @tmpio.write(*buf)
    end
  else
    def wbuf_writev(buf)
      @tmpio.kgio_writev(buf)
      buf.inject(0) { |n, s| n += s.size }
    end
  end

  def wbuf_write(c, buf)
    # try to bypass the VFS layer and write directly to the socket
    # if we're all caught up
    case rv = String === buf ? c.kgio_trywrite(buf) : c.kgio_trywritev(buf)
    when String, Array
      buf = rv # retry in loop
    when nil
      return # yay! hopefully we don't have to buffer again
    when :wait_writable, :wait_readable
      @busy = rv
    end until @busy

    @tmpio ||= Yahns::TmpIO.new(c.class.output_buffer_tmpdir)
    # n.b.: we rely on O_APPEND in TmpIO, here
    @sf_count += String === buf ? @tmpio.write(buf) : wbuf_writev(buf)

    # we spent some time copying to the FS, try to write to
    # the socket again in case some space opened up...
    case rv = c.trysendfile(@tmpio, @sf_offset, @sf_count)
    when Integer
      @sf_count -= rv
      @sf_offset += rv
    when :wait_writable, :wait_readable
      @busy = rv
      return rv
    else
      raise "BUG: #{rv.nil? ? "EOF" : rv.inspect} on tmpio " \
            "sf_offset=#@sf_offset sf_count=#@sf_count"
    end while @sf_count > 0

    # we're all caught up, try to prevent dirty data from getting flushed
    # to disk if we can help it.
    wbuf_abort
    @sf_offset = 0
    @busy = false
    nil
  end

  # called by last wbuf_flush
  def wbuf_close(client)
    wbuf_abort
    wbuf_close_common(client)
  end

  def wbuf_abort
    @tmpio = @tmpio.close if @tmpio
  end
end
