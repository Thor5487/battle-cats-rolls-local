# -*- encoding: binary -*-
# Copyright (C) 2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'stringio'
require_relative 'wbuf_common'

# This is only used for "proxy_buffering: false"
class Yahns::WbufLite # :nodoc:
  include Yahns::WbufCommon
  attr_reader :busy
  attr_writer :req_res

  def initialize(req_res)
    @tmpio = nil
    @sf_offset = @sf_count = 0
    @wbuf_persist = :ignore
    @busy = false
    @req_res = req_res
  end

  def wbuf_write(c, buf)
    buf = buf.join if Array === buf
    # try to bypass the VFS layer and write directly to the socket
    # if we're all caught up
    case rv = c.kgio_trywrite(buf)
    when String
      buf = rv # retry in loop
    when nil
      return # yay! hopefully we don't have to buffer again
    when :wait_writable, :wait_readable
      @busy = rv
    end until @busy

    @tmpio ||= StringIO.new(''.dup) # relies on encoding: binary above
    @tmpio.seek(0, 2) # fake O_APPEND behavior
    @sf_count += @tmpio.write(buf)

    # we spent some time copying to the FS, try to write to
    # the socket again in case some space opened up...
    case rv = c.trysendio(@tmpio, @sf_offset, @sf_count)
    when Integer
      @sf_count -= rv
      @sf_offset += rv
    when :wait_writable, :wait_readable
      @busy = rv
      return rv
    else
      raise "BUG: #{rv.nil? ? 'EOF' : rv.inspect} on " \
            "tmpio.size=#{@tmpio.size} " \
            "sf_offset=#@sf_offset sf_count=#@sf_count"
    end while @sf_count > 0

    # we're all caught up, try to save some memory if we can help it.
    wbuf_abort
    @busy = false
    nil
  rescue
    @req_res = @req_res.close if @req_res
    raise
  end

  def wbuf_flush(client)
    case rv = client.trysendio(@tmpio, @sf_offset, @sf_count)
    when Integer
      return wbuf_close(client) if (@sf_count -= rv) == 0 # all sent!
      @sf_offset += rv # keep going otherwise
    when :wait_writable, :wait_readable
      return rv
    else
      raise "BUG: #{rv.nil? ? 'EOF' : rv.inspect} on " \
            "tmpio.size=#{@tmpio.size} " \
            "sf_offset=#@sf_offset sf_count=#@sf_count"
    end while @sf_count > 0
    wbuf_close(client)
  rescue
    @wbuf_persist = false # ensure a hijack response is not called
    @req_res = @req_res.close if @req_res
    wbuf_close(client)
    raise
  end

  # called by Yahns::HttpClient#step_write
  def wbuf_close(client)
    wbuf_abort if @tmpio

    # resume the event loop when @blocked is empty
    # The actual Yahns::ReqRes#yahns_step is actually read/write-event
    # agnostic, and we should actually watch for writability here since
    # the req_res socket itself could be completely drained of readable
    # data and just waiting for another request (which we don't support, yet)
    if @req_res
      @busy = false
      client.hijack_cleanup
      Thread.current[:yahns_queue].queue_mod(@req_res, Yahns::Queue::QEV_WR)
      return :ignore
    end
    @wbuf_persist
  rescue
    @req_res = @req_res.close if @req_res
    raise
  end

  def wbuf_abort
    @sf_offset = @sf_count = 0
    # we can safely truncate since this is a StringIO, we cannot do this
    # with a real file because zero-copy with sendfile means truncating
    # a while could clobber in-flight data
    @tmpio.truncate(0)
  end
end
