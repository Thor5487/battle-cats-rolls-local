# frozen_string_literal: true

require_relative 'root'

require 'yaml'

module BattleCatsRolls
  module L10n
    def self.proofreader lang
      data.dig(lang, '') || '-'
    end

    def self.translate lang, text
      data.dig(lang, text) || text
    end

    def self.data
      @data ||= %w[en tw jp].inject({}) do |result, lang|
        result[lang] = YAML.load_file("#{Root}/data/#{lang}/l10n.yaml")
        result
      end
    end
  end
end
