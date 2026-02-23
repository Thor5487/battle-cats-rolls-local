# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# subclasses of Yahns::HttpClient will class extend this

module Yahns::HttpContext # :nodoc:
  attr_accessor :check_client_connection
  attr_accessor :client_body_buffer_size
  attr_accessor :client_header_buffer_size
  attr_accessor :client_max_body_size
  attr_accessor :input_buffering  # :lazy, true, false
  attr_accessor :output_buffering # true, false
  attr_accessor :persistent_connections # true or false only
  attr_accessor :client_timeout
  attr_accessor :qegg
  attr_accessor :queue # set right before spawning acceptors
  attr_reader :app
  attr_accessor :app_defaults
  attr_writer :input_buffer_tmpdir
  attr_accessor :output_buffer_tmpdir

  def http_ctx_init(yahns_rack)
    @yahns_rack = yahns_rack
    @app_defaults = yahns_rack.app_defaults
    @check_client_connection = false
    @client_body_buffer_size = 8 * 1024
    @client_header_buffer_size = 4000
    @client_max_body_size = 1024 * 1024 # nil => infinity
    @input_buffering = true
    @output_buffering = true
    @persistent_connections = true
    @client_timeout = 15
    @qegg = nil
    @queue = nil

    # Dir.tmpdir can change while running, so leave these as nil
    @input_buffer_tmpdir = nil
    @output_buffer_tmpdir = nil
  end

  # call this after forking
  def after_fork_init
    @app = __wrap_app(@yahns_rack.app_after_fork)
  end

  def __wrap_app(app)
    # input_buffering == false is handled in http_client
    return app if @client_max_body_size.nil?

    require_relative 'cap_input'
    return app if @input_buffering == true

    # @input_buffering == false/:lazy
    require_relative 'max_body'
    Yahns::MaxBody.new(app, @client_max_body_size)
  end

  # call this immediately after successful accept()/accept4()
  def logger=(l) # cold
    @logger = @app_defaults["rack.logger"] = l
  end

  def logger
    @app_defaults["rack.logger"]
  end

  def mkinput(client, hs)
    (@input_buffering ? Yahns::TeeInput : Yahns::StreamInput).new(client, hs)
  end

  def errors=(dest)
    @app_defaults["rack.errors"] = dest
  end

  def errors
    @app_defaults["rack.errors"]
  end

  def tmpio_for(len, env)
    # short requests are most common
    if len && len <= @client_body_buffer_size;
      # Can't use binmode, yet: https://bugs.ruby-lang.org/issues/11945
      tmp = StringIO.new(''.dup)
    else # too big or chunked, unknown length
      tmp = @input_buffer_tmpdir
      mbs = @client_max_body_size
      tmp = mbs ? Yahns::CapInput.new(mbs, tmp) : Yahns::TmpIO.new(tmp)
      (env['rack.tempfiles'] ||= []) << tmp
    end
    tmp
  end
end
