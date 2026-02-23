# To the extent possible under law, Eric Wong has waived all copyright and
# related or neighboring rights to this example.

# See yahns_config(5) manpage for more information

# By default, this based on the soft limit of RLIMIT_NOFILE
#   count = Process.getrlimit(:NOFILE)[0]) * 0.5
# yahns will start expiring idle clients once we hit it
client_expire_threshold 0.5

# This is highly recommended if you're daemonizing yahns
# Without it, Ruby backtrace logs can be lost.
stderr_path "/path/to/stderr.log"

# each queue definition configures a thread pool and epoll_wait usage
# The default queue is always present
queue(:default) do
  worker_threads 7 # this is the default value, highly app-dependent
  max_events 1 # 1: fairest, best in all multi-threaded cases
end

# This is an example of a small queue with fewer workers and unfair scheduling.
# It is rarely necessary or even advisable to configure multiple queues.
# Again, this is rarely necessary or even useful
queue(:small) do
  worker_threads 2

  # increase max_events only under one of the following circumstances:
  # 1) worker_threads is 1
  # 2) epoll_wait lock contention inside the kernel is the biggest bottleneck
  #    (this is unlikely outside of "hello world" apps)
  max_events 64
end

# This is an example of a Rack application configured in yahns.
# There must be at least one app configured for yahns to run.
# All values below are defaults
app(:rack, "/path/to/config.ru", preload: false) do
  # note: there is no listen default, this must be configured yourself
  listen 8080, backlog: 1024

  client_max_body_size 1024*1024
  check_client_connection false
  logger Logger.new($stderr)
  client_timeout 15
  input_buffering true
  output_buffering true # output buffering is always lazy if enabled
  persistent_connections true
  errors $stderr
  queue :default
end

# same as first, just listen on different port and small queue
app(:rack, "/path/to/config.ru") do
  listen "10.0.0.1:10000"
  client_max_body_size 1024*1024*10
  check_client_connection true
  logger Logger.new("/path/to/another/log")
  client_timeout 30
  persistent_connections true
  errors "/path/to/errors.log"
  queue :small
end

# totally different app
app(:rack, "/path/to/another.ru", preload: true) do
  listen 8081, sndbuf: 1024 * 1024
  listen "/path/to/unix.sock"
  client_max_body_size 1024*1024*1024
  input_buffering :lazy
  output_buffering false
  client_timeout 4
  persistent_connections false

  # different apps may share the same queue, but listen on different ports.
  queue :default
end

# yet another totally different app, this app is not-thread safe but fast
# enough for multi-process to not matter.
# Use unicorn if you need multi-process performance on single-threaded apps
app(:rack, "/path/to/not_thread_safe.ru") do
  # listeners _always_ get a private thread in yahns
  listen "/path/to/yet_another.sock"
  listen 8082

  # inline private/anonymous queue definition here
  queue do
    worker_threads 1 # single-threaded queue
    max_events 64 # very high max_events is perfectly fair for single thread
  end

  # single (or few)-threaded apps must use full buffering if serving
  # untrusted/slow clients.
  input_buffering true
  output_buffering true
end
# Note: this file is used by test_config.rb, be sure to update that
# if we update this
