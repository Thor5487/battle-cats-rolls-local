# frozen_string_literal: true

require 'zlib'
require 'base64'

module BattleCatsRolls
  module Owned
    module_function

    def encode cat_ids
      Base64.urlsafe_encode64(deflate(cat_ids.join(',')))
    end

    def decode base64
      inflate(Base64.urlsafe_decode64(base64)).split(',').map(&:to_i)
    rescue Zlib::BufError
      []
    end

    def deflate bytes
      Zlib::Deflate.deflate(bytes, Zlib::BEST_COMPRESSION)
    end

    def inflate bytes
      Zlib::Inflate.inflate(bytes)
    end
  end
end
