# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPLv2 or later (https://www.gnu.org/licenses/gpl-2.0.txt)
# frozen_string_literal: true

# Middleware used to enforce client_max_body_size for TeeInput users.
#
# There is no need to configure this middleware manually, it will
# automatically be configured for you based on the client_max_body_size
# setting.
#
# For more fine-grained control, you may also define it per-endpoint in
# your Rack config.ru like this:
#
#        map "/limit_1M" do
#          use Yahns::MaxBody, 1024*1024
#          run MyApp
#        end
#        map "/limit_10M" do
#          use Yahns::MaxBody, 1024*1024*10
#          run MyApp
#        end
class Yahns::MaxBody # :nodoc:
  # This is automatically called when used with Rack::Builder#use
  # See Yahns::MaxBody
  def initialize(app, limit)
    Integer === limit or raise ArgumentError, "limit not an Integer"
    @app = app
    @limit = limit
  end

  # our main Rack middleware endpoint
  def call(env) # :nodoc:
    catch(:yahns_EFBIG) do
      len = env['CONTENT_LENGTH']
      if len && len.to_i > @limit
        return err
      elsif /\Achunked\z/i =~ env['HTTP_TRANSFER_ENCODING']
        limit_input!(env)
      end
      @app.call(env)
    end || err
  end

  # Rack response returned when there's an error
  def err # :nodoc:
    [ 413, { 'Content-Length' => '0', 'Content-Type' => 'text/plain' }, [] ]
  end

  def limit_input!(env) # :nodoc:
    input = env['rack.input']
    klass = input.respond_to?(:rewind) ? RewindableWrapper : Wrapper
    env['rack.input'] = klass.new(input, @limit)
  end
end
require_relative 'max_body/wrapper'
require_relative 'max_body/rewindable_wrapper'
