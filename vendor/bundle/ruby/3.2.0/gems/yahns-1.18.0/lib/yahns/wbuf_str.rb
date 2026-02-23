# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'wbuf_common'

# we only use this for buffering the tiniest responses (which are already
# strings in memory and a handful of bytes).
#
#   "HTTP", "/1.1 "
#   "HTTP/1.1 100 Continue\r\n\r\n"
#   "100 Continue\r\n\r\nHTTP/1.1 "
#
# This is very, very rarely triggered.
# 1) check_client_connection is enabled
# 2) the client sent an "Expect: 100-continue" header
#
# Most output buffering goes through
# the normal Yahns::Wbuf class which uses a temporary file as a buffer
# (suitable for sendfile())
class Yahns::WbufStr # :nodoc:
  include Yahns::WbufCommon

  def initialize(str, next_state)
    @str = str
    @next = next_state # :ccc_done, :r100_done
  end

  def wbuf_flush(client)
    case rv = client.kgio_trywrite(@str)
    when String
      @str = rv
    when :wait_writable, :wait_readable
      return rv
    when nil
      return @next
    end while true
  end
end
