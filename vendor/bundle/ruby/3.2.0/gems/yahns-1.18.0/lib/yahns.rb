# Copyright (C) 2013-2019 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
$stdout.sync = $stderr.sync = true

require 'unicorn' # pulls in raindrops, kgio, fcntl, etc, stringio, and logger
require 'sleepy_penguin'
require 'io/wait'

# kill off some unicorn internals we don't need
# we'll probably just make kcar into a server parser so we don't depend
# on unicorn at all
[ :ClientShutdown, :Const, :SocketHelper, :StreamInput, :TeeInput,
  :SSLConfigurator, :Configurator, :TmpIO, :Util, :Worker, :SSLServer,
  :HttpServer ].each do |sym|
    Unicorn.__send__(:remove_const, sym) if Unicorn.const_defined?(sym)
end

# yahns exposes little user-visible API outside of the config file.
# See https://yhbt.net/yahns/yahns_config.txt
# for the config documentation (or yahns_config(5) manpage)
# and https://yhbt.net/yahns.git/about/ for the homepage.
#
# Yahns::ProxyPass is currently the only public API.
#
# Documented APIs and options are supported forever,
# internals are subject to change.
module Yahns
  # :stopdoc:
  # We populate this at startup so we can figure out how to reexecute
  # and upgrade the currently running instance of yahns
  # Unlike unicorn, this Hash is NOT a stable/public interface.
  #
  # * 0 - the path to the yahns executable
  # * :argv - a deep copy of the ARGV array the executable originally saw
  # * :cwd - the working directory of the application, this is where
  # you originally started yahns.
  #
  # To change your yahns executable to a different path without downtime,
  # you can set the following in your yahns config file, HUP and then
  # continue with the traditional USR2 + QUIT upgrade steps:
  #
  #   Yahns::START[0] = "/home/bofh/2.0.0/bin/yahns"
  START = {
    :argv => ARGV.map(&:dup),
    0 => $0.dup,
  }

  # We favor ENV['PWD'] since it is (usually) symlink aware for Capistrano
  # and like systems
  START[:cwd] = begin
    a = File.stat(pwd = ENV['PWD'])
    b = File.stat(Dir.pwd)
    a.ino == b.ino && a.dev == b.dev ? pwd : Dir.pwd
  rescue
    Dir.pwd
  end

  # Raised inside TeeInput when a client closes the socket inside the
  # application dispatch.  This is always raised with an empty backtrace
  # since there is nothing in the application stack that is responsible
  # for client shutdowns/disconnects.
  ClientShutdown = Class.new(EOFError) # :nodoc:

  ClientTimeout = Class.new(RuntimeError) # :nodoc:

  # try to use the monotonic clock in Ruby >= 2.1, it is immune to clock
  # offset adjustments and generates less garbage (Float vs Time object)
  begin
    def self.now # :nodoc:
      Process.clock_gettime(Process::CLOCK_MONOTONIC) # :nodoc:
    end
  rescue NameError, NoMethodError
    def self.now # :nodoc:
      Time.now.to_f # Ruby <= 2.0
    end
  end

  # :startdoc:
end

# FIXME: require lazily
require_relative 'yahns/log'
require_relative 'yahns/queue'
require_relative 'yahns/stream_input'
require_relative 'yahns/tee_input'
require_relative 'yahns/queue_egg'
require_relative 'yahns/http_response'
require_relative 'yahns/http_client'
require_relative 'yahns/http_context'
require_relative 'yahns/queue'
require_relative 'yahns/config'
require_relative 'yahns/tmpio'
require_relative 'yahns/worker'
require_relative 'yahns/sigevent'
require_relative 'yahns/socket_helper'
require_relative 'yahns/server'
require_relative 'yahns/fdmap'
require_relative 'yahns/acceptor'
require_relative 'yahns/wbuf'
require_relative 'yahns/version'
