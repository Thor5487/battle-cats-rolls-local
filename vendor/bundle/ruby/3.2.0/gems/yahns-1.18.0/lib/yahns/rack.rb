# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'rack'
class Yahns::Rack # :nodoc:
  attr_reader :preload

  # enforce a single instance for the identical config.ru
  def self.instance_key(*args)
    ru = args[0]

    # it's safe to expand_path now since we enforce working_directory in the
    # top-level config is called before any apps are created
    # ru may also be a Rack::Builder object or any already-built Rack app
    ru.respond_to?(:call) ? ru.object_id : File.expand_path(ru)
  end

  def initialize(ru, opts = {})
    # always called after config file parsing, may be called after forking
    @app = lambda do
      if ru.respond_to?(:call)
        inner_app = ru.respond_to?(:to_app) ? ru.to_app : ru
      else
        inner_app = case ru
        when /\.ru$/
          raw = File.read(ru)
          raw.sub!(/^__END__\n.*/, '')
          eval("Rack::Builder.new {(\n#{raw}\n)}.to_app", TOPLEVEL_BINDING, ru)
        else
          require ru
          Object.const_get(File.basename(ru, '.rb').capitalize)
        end
      end
      inner_app
    end
    @ru = ru
    @preload = opts[:preload]
    build_app! if @preload
  end

  def config_context
    ctx_class = Class.new(Yahns::HttpClient)
    ctx_class.extend(Yahns::HttpContext)
    ctx_class.http_ctx_init(self)
    ctx_class
  end

  def build_app!
    if @app.respond_to?(:arity) && @app.arity == 0
      Gem.refresh if defined?(Gem) && Gem.respond_to?(:refresh)
      @app = @app.call
    end
  end

  # allow different HttpContext instances to have different Rack defaults
  def app_defaults
    {
      # logger is set in http_context
      "rack.errors" => $stderr,
      "rack.multiprocess" => true,
      "rack.multithread" => true,
      "rack.run_once" => false,
      "rack.hijack?" => true,
      "rack.version" => [ 1, 2 ],
      "SCRIPT_NAME" => ''.dup,

      # this is not in the Rack spec, but some apps may rely on it
      "SERVER_SOFTWARE" => 'yahns'.dup
    }
  end

  def app_after_fork
    build_app! unless @preload
    @app
  end
end

# register ourselves
Yahns::Config::APP_CLASS[:rack] = Yahns::Rack
