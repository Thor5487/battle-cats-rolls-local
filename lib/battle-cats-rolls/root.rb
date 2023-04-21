# frozen_string_literal: true

module BattleCatsRolls
  Root = File.expand_path("#{__dir__}/../..").freeze
  WebHost = ENV['WEB_HOST'].freeze
  WebPort = ENV['WEB_YAHNS'].freeze || 8080
  SeekHost = ENV['SEEK_HOST'].freeze
  SeekPort = ENV['SEEK_YAHNS'].freeze || 9090
end
