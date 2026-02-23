# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (see COPYING for details)
# frozen_string_literal: true
require_relative 'acceptor'
class Yahns::TCPServer < Kgio::TCPServer # :nodoc:
  include Yahns::Acceptor
end
