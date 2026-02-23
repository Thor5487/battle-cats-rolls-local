# To the extent possible under law, Eric Wong has waived all copyright and
# related or neighboring rights to this example.
#
# See examples/proxy_pass.ru for the complementary rackup file
# <https://yhbt.net/yahns.git/tree/examples/proxy_pass.ru>

# Setup an OpenSSL context:
require 'openssl'
ssl_ctx = OpenSSL::SSL::SSLContext.new
ssl_ctx.cert = OpenSSL::X509::Certificate.new(
  File.read('/etc/ssl/certs/example.crt')
)
ssl_ctx.extra_chain_cert = [
  OpenSSL::X509::Certificate.new(
    File.read('/etc/ssl/certs/chain.crt')
  )
]
ssl_ctx.key = OpenSSL::PKey::RSA.new(
  File.read('/etc/ssl/private/example.key')
)

# use defaults provided by Ruby on top of OpenSSL,
# but disable client certificate verification as it is rare for servers:
ssl_ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)

# Built-in session cache (only useful if worker_processes is nil or 1)
ssl_ctx.session_cache_mode = OpenSSL::SSL::SSLContext::SESSION_CACHE_SERVER

worker_processes 1
app(:rack, "/path/to/proxy_pass.ru", preload: true) do
  listen 443, ssl_ctx: ssl_ctx
  listen '[::]:443', ipv6only: true, ssl_ctx: ssl_ctx
end

stdout_path "/path/to/my_logs/out.log"
stderr_path "/path/to/my_logs/err.log"
