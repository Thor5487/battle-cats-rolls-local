# To the extent possible under law, Eric Wong has waived all copyright and
# related or neighboring rights to this examples
# A typical Rack example for hosting a single Rack application with yahns
# and only frequently-useful config values
#
# See yahns_config(5) manpage for more information

worker_processes(1) do
  # these names are based on pthread_atfork(3) documentation
  atfork_child do
    defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection
    puts "#$$ yahns worker is running"
  end
  atfork_prepare do
    defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
    puts "#$$ yahns parent about to spawn"
  end
  atfork_parent do
    puts "#$$ yahns parent done spawning"
  end
end

# working_directory "/path/to/my_app"
stdout_path "/path/to/my_logs/out.log"
stderr_path "/path/to/my_logs/err.log"
pid "/path/to/my_pids/yahns.pid"
client_expire_threshold 0.5

queue do
  worker_threads 50
end

app(:rack, "config.ru", preload: false) do
  listen 80

  # See yahns_config(5) and OpenSSL::SSL::SSLContext on configuring
  # HTTPS support
  # listen 443, ssl_ctx: ...

  client_max_body_size 1024 * 1024
  input_buffering true
  output_buffering true # this lazy by default
  client_timeout 5
  persistent_connections true
end

# Note: this file is used by test_config.rb, be sure to update that
# if we update this
