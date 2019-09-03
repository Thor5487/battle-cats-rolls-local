# frozen_string_literal: true

require 'openssl'
require 'digest/md5'

module BattleCatsRolls
  class Unpacker < Struct.new(
    :ecb_key,
    :cbc_key, :cbc_iv,
    :bad_data, keyword_init: true)
    def self.for_list
      new(ecb_key: Digest::MD5.hexdigest('pack')[0, 16])
    end

    def self.for_pack
      new(
        ecb_key: Digest::MD5.hexdigest('battlecats')[0, 16],
        cbc_key: ['d754868de89d717fa9e7b06da45ae9e3'].pack('H*'),
        cbc_iv: ['40b2131a9f388ad4e5002a98118f6128'].pack('H*'))
    end

    def decrypt data
      if bad_data
        data
      else
        safe_decrypt do
          decrypt_aes_128_ecb(data)
        end || safe_decrypt do
          decrypt_aes_128_cbc(data)
        end || begin
          warn "#{bad_data.class}:#{bad_data}, turning off decryption"
          data
        end
      end
    end

    private

    def safe_decrypt
      self.bad_data = nil
      result = yield.force_encoding('UTF-8')
      result if result.valid_encoding?
    rescue OpenSSL::Cipher::CipherError => e
      self.bad_data = e
      nil
    end

    def decrypt_aes_128_ecb data
      cipher = OpenSSL::Cipher.new('aes-128-ecb')
      cipher.decrypt
      cipher.key = ecb_key
      cipher.update(data) + cipher.final
    end

    def decrypt_aes_128_cbc data
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      cipher.decrypt
      cipher.key = cbc_key
      cipher.iv = cbc_iv
      cipher.update(data) + cipher.final
    end
  end
end
