# frozen_string_literal: true

module BattleCatsRolls
  class Fruit < Struct.new(:seed, :version)
    def value
      @value ||=
        case version
        when '8.6', '8.5'
          seed
        when '8.4'
          [seed, alternative_seed].min
        else
          raise "Unknown version: #{version}"
        end
    end

    private

    def alternative_seed
      0x100000000 - seed
    end
  end
end
