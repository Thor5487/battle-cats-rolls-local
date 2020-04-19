# frozen_string_literal: true

require_relative 'route'
require_relative 'request'
require_relative 'seek_seed'
require_relative 'cache'
require_relative 'aws_auth'
require_relative 'view'
require_relative 'help'

require 'jellyfish'

require 'json'
require 'net/http'

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
      Route.ball_en
      Route.ball_tw
      Route.ball_jp
      View.warmup
      'OK'
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
      render :logs
    end

    class Seek
      include Jellyfish
      controller_include NormalizedPath, Imp

      (%w[/en /tw /jp /kr] << '').each do |prefix|
        %w[gatya.tsv item.tsv sale.tsv].each do |file|
          lang = prefix[1..-1] || 'jp'

          get "/seek#{prefix}/#{file}" do
            headers 'Content-Type' => 'text/plain; charset=utf-8'
            body serve_tsv(lang, file)
          end

          get "/seek#{prefix}/curl/#{file}" do
            headers 'Content-Type' => 'text/plain; charset=utf-8'
            body "#{aws_auth(lang, file).to_curl}\n"
          end

          get "/seek#{prefix}/json/#{file}" do
            headers 'Content-Type' => 'application/json; charset=utf-8'
            body JSON.dump(aws_auth(lang, file).headers)
          end
        end
      end

      get '/seek' do
        render :seek, queue_size: SeekSeed.queue.size
      end

      post '/seek/enqueue' do
        key = SeekSeed.enqueue(route.seek_source, cache, logger)

        found route.seek_result(key)
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
