# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'raindrops'

# included in Yahns::HttpClient
#
# this provides the ability to expire idle clients once we hit a soft limit
# on idle clients
#
# we absolutely DO NOT issue IO#close in here, only BasicSocket#shutdown
module Yahns::ClientExpireTCPI # :nodoc:
  def yahns_expire(timeout) # rarely called
    return 0 if closed?

    info = Raindrops::TCP_Info.new(self)
    return 0 if info.state != 1 # TCP_ESTABLISHED == 1

    # Linux struct tcp_info timers are in milliseconds
    timeout *= 1000

    send_timedout = !!(info.last_data_sent > timeout)

    # tcpi_last_data_recv is not valid unless tcpi_ato (ACK timeout) is set
    if 0 == info.ato
      sd = send_timedout && (info.last_ack_recv > timeout)
    else
      sd = send_timedout && (info.last_data_recv > timeout)
    end
    if sd
      shutdown
      1
    else
      0
    end
  # shutdown may race with the shutdown in http_response_done
  rescue
    0
  end
# FreeBSD has "struct tcp_info", too, but does not support all the fields
# Linux does as of FreeBSD 9 (haven't checked FreeBSD 10, yet).
end if RUBY_PLATFORM.include?('linux')
