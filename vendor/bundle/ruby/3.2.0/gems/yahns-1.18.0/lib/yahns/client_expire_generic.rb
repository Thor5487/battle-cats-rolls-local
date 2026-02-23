# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
module Yahns::ClientExpireGeneric # :nodoc:
  def __timestamp
    Yahns.now
  end

  def yahns_init
    super # Yahns::HttpClient#yahns_init
    @last_io_at = 0
  end

  def yahns_expire(timeout)
    return 0 if closed?
    if (__timestamp - @last_io_at) > timeout
      shutdown
      1
    else
      0
    end
  # shutdown may race with the shutdown in http_response_done
  rescue
    0
  end

  def kgio_trywrite(*args)
    @last_io_at = __timestamp
    super
  end

  def kgio_tryread(*args)
    @last_io_at = __timestamp
    super
  end

  def trysendfile(*args)
    @last_io_at = __timestamp
    super
  end
end
