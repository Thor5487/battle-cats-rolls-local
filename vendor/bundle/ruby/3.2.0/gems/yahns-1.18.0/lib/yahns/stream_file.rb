# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'wbuf_common'

class Yahns::StreamFile # :nodoc:
  include Yahns::WbufCommon

  # do not use this in your app (or any of our API)
  NeedClose = Class.new(File) # :nodoc:

  def initialize(body, persist, offset, count)
    path = body.to_path
    if path =~ %r{\A/dev/fd/(\d+)\z}
      @tmpio = IO.for_fd($1.to_i)
      @tmpio.autoclose = false
    else
      retried = false
      begin
        @tmpio = NeedClose.open(path)
      rescue Errno::EMFILE, Errno::ENFILE
        raise if retried
        retried = true
        Thread.current[:yahns_fdmap].desperate_expire(5)
        sleep(1)
        retry
      end
    end
    @sf_offset = offset || 0
    @sf_count = count
    @wbuf_persist = persist # whether or not we keep the connection alive
    @body = body
  end

  # called by last wbuf_flush,
  # returns true / false for persistent/non-persistent connections,
  # :ignore for hijacked connections
  def wbuf_close(client)
    @tmpio.close if NeedClose === @tmpio
    wbuf_close_common(client)
  end
end
