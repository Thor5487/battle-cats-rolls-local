# frozen_string_literal: true

require_relative 'ability'

module BattleCatsRolls
  module TalentUtility
    include AbilityUtility

    def values_range values, suffix=''
      result = values.uniq
      first_value = "#{result.first}#{suffix}"

      if result.size > 1
        last_value = "#{result.last}#{suffix}"
        "#{first_value} ~ #{highlight(last_value)}"
      else
        highlight(first_value)
      end
    end
  end

  class Talent < Struct.new(:key, :data, :ability)
    class IncreaseHealth < Talent
      include TalentUtility

      def name
        'Increase health'
      end

      def display
        "Increase by #{min}% ~ #{percent(max)} by #{level} levels"
      end
    end

    class IncreaseDamage < Talent
      include TalentUtility

      def name
        'Increase damage'
      end

      def display
        "Increase by #{min}% ~ #{percent(max)} by #{level} levels"
      end
    end

    class IncreaseSpeed < Talent
      include TalentUtility

      def name
        'Increase speed'
      end

      def display
        "Increase by #{min} ~ #{highlight(max)} by #{level} levels"
      end
    end

    class ReduceCost < Talent
      include TalentUtility

      def name
        'Reduce cost'
      end

      def display
        "Reduce by #{min} ~ #{highlight(max)} by #{level} levels"
      end

      private

      def min
        (super * chapter2_cost_multiplier).round
      end

      def max
        (super * chapter2_cost_multiplier).round
      end

      def chapter2_cost_multiplier
        1.5
      end
    end

    class Against < Talent
      def initialize(...)
        super
        self.ability = Ability::Specialization.new(
          [key.delete_prefix('against_').capitalize])
      end
    end

    Ability::Specialization::List.each do |type|
      const_set("Against#{type.capitalize}", Against)
    end

    class LootMoney < Talent
      def initialize(...)
        super
        self.ability = Ability::LootMoney.new
      end
    end

    class Strengthen < Talent
      include TalentUtility

      def initialize(...)
        super
        self.ability = Ability::Strengthen.new
      end

      def display
        threshold = data.dig('minmax', 0)
        modifiers = data.dig('minmax', 1).map{ |p| p + 100 }

        display_text = ability.display(
          threshold: values_range(threshold, '%'),
          modifier: values_range(modifiers, '%'))

        "#{display_text} by #{level} levels"
      end
    end

    class ResistantWave < Talent
      include TalentUtility

      def name
        'Resistant to'
      end

      def display
        "Reduce wave damage by #{values_range(data.dig('minmax', 0), '%')} by #{level} levels"
      end
    end

    def self.build info
      return [] unless info['talent']

      info['talent'].map do |key, data|
        const_get(constant_name(key), false).new(key, data)
      end
    end

    def self.constant_name key
      key.gsub(/(?:^|_)(\w)/) do |letter|
        letter[-1].upcase
      end
    end

    def name
      ability.name
    end

    def display
      ability.display
    end

    def level
      data.dig('max_level')
    end

    def min n=0
      data.dig('minmax', n, 0)
    end

    def max n=0
      data.dig('minmax', n, 1)
    end
  end
end
