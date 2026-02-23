# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative '../yahns'

module Yahns::RackupHandler # :nodoc:
  def self.default_host
    environment  = ENV['RACK_ENV'] || 'development'
    environment == 'development' ? '127.0.0.1' : '0.0.0.0'
  end

  def self.run(app, o)
    cfg = Yahns::Config.new
    cfg.instance_eval do
      # we need this because "rackup -D" sends us to "/", which might be
      # fine for most apps, but we have SIGUSR2 restarts to support
      working_directory(Yahns::START[:cwd])

      app(:rack, app) do # Yahns::Config#app
        addr = o[:listen] || "#{o[:Host]||default_host}:#{o[:Port]||8080}"
        # allow listening to multiple addresses (Yahns::Config#listen)
        addr.split(',').each { |l| listen(l) } unless addr == 'inherit'

        val = o[:client_timeout] and client_timeout(val)
      end

      queue do
        wt = o[:worker_threads] and worker_threads(wt)
      end

      %w(stderr_path stdout_path).each do |x|
        val = o[x] and __send__(x, val)
      end
    end
    Yahns::Server.new(cfg).start.join
  end

  # this is called by Rack::Server
  def self.valid_options
    # these should be the most common options
    {
      "listen=ADDRESS" => "address(es) to listen on (e.g. /tmp/sock)",
      "worker_threads=NUM" => "number of worker threads to run",

      # this affects how quickly graceful shutdown goes
      "client_timeout=SECONDS" => "timeout for idle clients",

      # I don't want these here, but rackup supports daemonize and
      # we lose useful information when that sends stdout/stderr to /dev/null
      "stderr_path=PATH" => "stderr destination",
      "stdout_path=PATH" => "stdout destination",
    }
  end
end
