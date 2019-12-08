# frozen_string_literal: true

require_relative 'cat'

module BattleCatsRolls
  class CatGuaranteed < Cat
    def track_label
      "#{super}G"
    end
  end
end
