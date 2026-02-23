# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

require_relative 'acceptor'
require_relative 'openssl_client'

class Yahns::OpenSSLServer < Kgio::TCPServer # :nodoc:
  include Yahns::Acceptor

  def self.wrap(fd, ssl_ctx)
    srv = for_fd(fd)
    srv.instance_variable_set(:@ssl_ctx, ssl_ctx)
    srv
  end

  def kgio_accept(klass, flags)
    io = super
    io.yahns_init_ssl(@ssl_ctx)
    io
  end
end
