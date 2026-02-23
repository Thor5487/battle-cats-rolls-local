# -*- encoding: binary -*-
# Copyright (C) 2013-2019 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'socket'
require 'rack/request'
require 'timeout' # only for Timeout::Error
require_relative 'proxy_http_response'
require_relative 'req_res'

# Yahns::ProxyPass is a Rack (hijack) app which allows yahns to
# act as a fully-buffering reverse proxy to protect backends
# from slow HTTP clients.
#
# Yahns::ProxyPass relies on the default behavior of yahns to do
# full input and output buffering. Output buffering is lazy,
# meaning it allows streaming output in the best case and
# will only buffer if the client cannot keep up with the server.
#
# The goal of this reverse proxy is to act as a sponge on the same LAN
# or host to any backend HTTP server not optimized for slow clients.
# Yahns::ProxyPass accomplishes this by handling all the slow clients
# internally within yahns itself to minimize time spent in the backend
# HTTP server waiting on slow clients.
#
# It does not do load balancing (we rely on Varnish for that).
# Here is the exact config we use with Varnish, which uses
# the +:response_headers+ option to hide some Varnish headers
# from clients:
#
#    run Yahns::ProxyPass.new('http://127.0.0.1:6081',
#            response_headers: {
#              'Age' => :ignore,
#              'X-Varnish' => :ignore,
#              'Via' => :ignore
#            })
#
# This is NOT a generic Rack app and must be run with yahns.
# It uses +rack.hijack+, so compatibility with logging
# middlewares (e.g. Rack::CommonLogger) is not great and
# timing information gets lost.
#
# This provides HTTPS termination for our mail archives:
# https://yhbt.net/yahns-public/
#
# See https://yhbt.net/yahns.git/tree/examples/https_proxy_pass.conf.rb
# and https://yhbt.net/yahns.git/tree/examples/proxy_pass.ru for examples
class Yahns::ProxyPass
  attr_reader :proxy_buffering, :response_headers # :nodoc:

  # +dest+ must be an HTTP URL with optional variables prefixed with '$'.
  # +dest+ may refer to the path to a Unix domain socket in the form:
  #
  #     unix:/absolute/path/to/socket
  #
  # Variables which may be used in the +dest+ parameter include:
  #
  # - $url - the entire URL used to make the request
  # - $path - the unescaped PATH_INFO of the HTTP request
  # - $fullpath - $path with QUERY_STRING
  # - $host - the hostname in the Host: header
  #
  # For Unix domain sockets, variables may be separated from the
  # socket path via: ":/".  For example:
  #
  #     unix:/absolute/path/to/socket:/$host/$fullpath
  #
  # Currently :response_headers is the only +opts+ supported.
  # :response_headers is a Hash containing a "from => to" mapping
  # of response headers.  The special value of +:ignore+ indicates
  # the header from the backend HTTP server will be ignored instead
  # of being blindly passed on to the client.
  def initialize(dest, opts = { response_headers: { 'Server' => :ignore } })
    case dest
    when %r{\Aunix:([^:]+)(?::(/.*))?\z}
      path = $2
      @sockaddr = Socket.sockaddr_un($1)
    when %r{\Ahttp://([^/]+)(/.*)?\z}
      path = $2
      host, port = $1.split(':')
      @sockaddr = Socket.sockaddr_in(port || 80, host)
    else
      raise ArgumentError, "destination must be an HTTP URL or unix: path"
    end
    @response_headers = opts[:response_headers] || {}
    @proxy_buffering = opts[:proxy_buffering]
    @proxy_buffering = true if @proxy_buffering.nil? # allow false

    # It's wrong to send the backend Server tag through.  Let users say
    # { "Server => "yahns" } if they want to advertise for us, but don't
    # advertise by default (for security)
    @response_headers['Server'] ||= :ignore
    init_path_vars(path)
  end

  def init_path_vars(path) # :nodoc:
    path ||= '$fullpath'
    # methods from Rack::Request we want:
    allow = %w(fullpath host_with_port host port url path)
    want = path.scan(/\$(\w+)/).flatten! || []
    diff = want - allow
    diff.empty? or
             raise ArgumentError, "vars not allowed: #{diff.uniq.join(' ')}"

    # kill leading slash just in case...
    @path = path.gsub(%r{\A/(\$(?:fullpath|path))}, '\1')
  end

  def call(env) # :nodoc:
    # 3-way handshake for TCP backends while we generate the request header
    rr = Yahns::ReqRes.start(@sockaddr)
    c = env['rack.hijack'].call # Yahns::HttpClient#call

    req = Rack::Request.new(env)
    req = @path.gsub(/\$(\w+)/) { req.__send__($1) }

    # start the connection asynchronously and early so TCP can do a
    case ver = env['HTTP_VERSION']
    when 'HTTP/1.1' # leave alone, response may be chunked
    else # no chunking for HTTP/1.0 and HTTP/0.9
      ver = 'HTTP/1.0'.freeze
    end

    addr = env['REMOTE_ADDR']
    xff = env['HTTP_X_FORWARDED_FOR']
    xff = xff =~ /\S/ ? "#{xff}, #{addr}" : addr
    req = "#{env['REQUEST_METHOD']} #{req} #{ver}\r\n" \
          "X-Forwarded-Proto: #{env['rack.url_scheme']}\r\n" \
          "X-Forwarded-For: #{xff}\r\n".dup

    # pass most HTTP_* headers through as-is
    chunked = false
    env.each do |key, val|
      %r{\AHTTP_(\w+)\z} =~ key or next
      key = $1
      # trailers are folded into the header, so do not send the Trailer:
      # header in the request
      next if /\A(?:VERSION|CONNECTION|KEEP_ALIVE|X_FORWARDED_FOR|TRAILER)/ =~
         key
      'TRANSFER_ENCODING'.freeze == key && val =~ /\bchunked\b/i and
        chunked = true
      key.tr!('_'.freeze, '-'.freeze)
      req << "#{key}: #{val}\r\n"
    end

    # special cases which Rack does not prefix:
    ctype = env["CONTENT_TYPE"] and req << "Content-Type: #{ctype}\r\n"
    clen = env["CONTENT_LENGTH"] and req << "Content-Length: #{clen}\r\n"
    input = chunked || (clen && clen.to_i > 0) ? env['rack.input'] : nil

    # finally, prepare to emit the headers
    rr.req_start(c, req << "\r\n".freeze, input, chunked, self)

    # this probably breaks fewer middlewares than returning whatever else...
    [ 500, [], [] ]
  rescue => e
    Yahns::Log.exception(env['rack.logger'], 'proxy_pass', e)
    [ 502, { 'Content-Length' => '0', 'Content-Type' => 'text/plain' }, [] ]
  end
end
