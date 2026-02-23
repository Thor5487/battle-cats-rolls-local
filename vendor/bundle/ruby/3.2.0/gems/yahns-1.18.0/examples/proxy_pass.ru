# To the extent possible under law, Eric Wong has waived all copyright and
# related or neighboring rights to this example.
#
# See examples/https_proxy_pass.conf.rb for the complementary rackup file
# <https://yhbt.net/yahns.git/tree/examples/https_proxy_pass.conf.rb>

# optionally, intercept static requests with Rack::Static middleware:
# use Rack::Static, root: '/path/to/public', gzip: true

require 'yahns/proxy_pass'
run Yahns::ProxyPass.new('http://127.0.0.1:6081')
