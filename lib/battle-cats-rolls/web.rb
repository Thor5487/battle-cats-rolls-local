# frozen_string_literal: true

require_relative 'route'
require_relative 'request'
require_relative 'seek_seed'
require_relative 'cache'
require_relative 'aws_auth'
require_relative 'aws_cf'
require_relative 'stat'
require_relative 'view'
require_relative 'help'

require 'jellyfish'

require 'json'
require 'net/http'
require 'digest/sha1'

module BattleCatsRolls
  class Web
    module Imp
      def route
        @route ||= Route.new(request)
      end

      def request
        @request ||= Request.new(env)
      end

      def serve_tsv lang, file
        key = "#{lang}/#{file}"

        cache[key] ||
          cache.store(
            key, request_tsv(lang, file), expires_in: route.tsv_expires_in)
      end

      def request_tsv lang, file
        aws = aws_auth(lang, file)
        request = Net::HTTP::Get.new(aws.uri)

        aws.headers.each do |key, value|
          request[key] = value
        end

        response = Net::HTTP.start(
          aws.uri.hostname,
          aws.uri.port,
          use_ssl: true) do |http|
          http.request(request)
        end

        response.body
      end

      def aws_auth lang, file
        prefix =
          case lang
          when 'jp'
            ''
          else
            lang
          end

        url =
          "https://nyanko-events-prd.s3.ap-northeast-1.amazonaws.com/battlecats#{prefix}_production/#{file}"

        AwsAuth.new(:get, url)
      end

      def throttle_ip
        key = "#{request.path} #{request.ip}"

        if cache[key]
          render :throttled
        else
          cache.store(key, '1', expires_in: route.throttle_ip_expires_in)
          yield(lambda{ cache.delete(key) })
        end
      end

      def guard_referrer
        allowed_domains =
          %r{\A
            https?://
              (?:
                #{Regexp.escape(route.web_host)}
              |
                #{Regexp.escape(route.seek_host)}
              )/}x

        if allowed_domains.match?(request.referrer)
          yield
        else
          not_found
        end
      end

      def cache
        @cache ||= Cache.default(logger)
      end

      def logger
        @logger ||= env['rack.logger'] || begin
          require 'logger'
          Logger.new(env['rack.errors'])
        end
      end

      def render name, arg=nil
        View.new(route, arg).render(name)
      end
    end

    include Jellyfish
    controller_include NormalizedPath, Imp

    get '/' do
      canonical_uri = route.uri(path: '/')

      if request.fullpath.sub(/&pick=[^&]+\z/, '') != canonical_uri
        found canonical_uri
      elsif route.show_tracks?
        cats, found_cats = route.prepare_tracks

        render :index, cats: cats, found_cats: found_cats, details: true
      else
        render :index
      end
    end

    get '/warmup' do
      cache
      Route.reload_balls
      View.warmup
      'OK'
    end

    get %r{^/cats/(?<id>\d+)} do |m|
      id = m[:id].to_i

      stats =
        if cat_data = route.ball.cats_map[id]
          cat_data.values_at('name', 'desc', 'stat').
            transpose.map do |(name, desc, stat)|
              Stat.new(id: id, name: name, desc: desc, stat: stat, level: 30)
            end
        else
          []
        end

      render :stats, stats: stats
    end

    get '/cats' do
      canonical_uri = route.uri(path: '/cats')

      if request.fullpath != canonical_uri
        found canonical_uri
      else
        render :cats, cats: route.cats
      end
    end

    get '/help' do
      render :help, help: Help.new
    end

    get '/logs' do
      guard_referrer do
        render :logs
      end
    end

    class Seek
      include Jellyfish
      controller_include NormalizedPath, Imp

      (%w[/en /tw /jp /kr] << '').each do |prefix|
        %w[gatya.tsv item.tsv sale.tsv].each do |file|
          lang = prefix[1..-1] || 'jp'

          get "/seek#{prefix}/#{file}" do
            guard_referrer do
              headers 'Content-Type' => 'text/plain; charset=utf-8'
              body serve_tsv(lang, file)
            end
          end

          get "/seek#{prefix}/curl/#{file}" do
            guard_referrer do
              headers 'Content-Type' => 'text/plain; charset=utf-8'
              body "#{aws_auth(lang, file).to_curl}\n"
            end
          end

          get "/seek#{prefix}/json/#{file}" do
            guard_referrer do
              headers 'Content-Type' => 'application/json; charset=utf-8'
              body JSON.dump(aws_auth(lang, file).headers)
            end
          end
        end
      end

      get %r{^/seek/webview/(?<path>.+)} do |m|
        aws = AwsCf.new("https://nyanko-webview.ponosgames.com/#{m[:path]}")

        found aws.generate
      end

      get '/seek' do
        render :seek, queue_size: SeekSeed.queue.size
      end

      post '/seek/enqueue' do
        source = route.seek_source
        key = Digest::SHA1.hexdigest(source)

        if cache[key]
          found route.seek_result(key)
        else
          throttle_ip do |clear_throttle|
            SeekSeed.enqueue(source, key, logger, cache, clear_throttle)

            found route.seek_result(key)
          end
        end
      end

      get %r{^/seek/result/?(?<key>\w*)} do |m|
        key = m[:key]
        seed = cache[key] if /./.match?(key)
        seek = SeekSeed.queue[key]

        seek.yield if seek&.ended?

        render :seek_result, seed: seed, seek: seek
      end
    end
  end
end
