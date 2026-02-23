# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
module Yahns::WbufCommon # :nodoc:
  # returns true / false for persistent/non-persistent connections
  # returns :wait_*able when blocked
  # returns :ignore if hijacked
  # currently, we rely on each thread having exclusive access to the
  # client socket, so this is never called concurrently with wbuf_write
  def wbuf_flush(client)
    case rv = client.trysendfile(@tmpio, @sf_offset, @sf_count)
    when Integer
      if (@sf_count -= rv) == 0 # all sent!
        @sf_offset = 0
        return wbuf_close(client)
      end

      @sf_offset += rv # keep going otherwise
    when :wait_writable, :wait_readable
      return rv
    when nil
      # response got truncated, drop the connection
      # this may happens when using Rack::File or similar, we can't
      # keep the connection alive because we already sent our Content-Length
      # header the client would be confused.
      @wbuf_persist = false
      return wbuf_close(client)
    else
      raise "BUG: rv=#{rv.inspect} " \
            "on tmpio=#{@tmpio.inspect} " \
            "sf_offset=#@sf_offset sf_count=#@sf_count"
    end while @sf_count > 0
    wbuf_close(client)
  rescue
    @wbuf_persist = false # ensure a hijack response is not called
    wbuf_close(client)
    raise
  end

  def wbuf_close_common(client)
    @body.close if @body.respond_to?(:close)
    if @wbuf_persist.respond_to?(:call) # hijack
      client.response_hijacked(@wbuf_persist) # :ignore
    else
      @wbuf_persist # true, false, :ignore, or Yahns::StreamFile
    end
  end
end
