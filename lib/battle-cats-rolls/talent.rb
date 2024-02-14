# frozen_string_literal: true

require_relative 'ability'

module BattleCatsRolls
  module TalentUtility
    include AbilityUtility

    def values_range values, suffix: '', show: :itself.to_proc
      result = values.uniq
      first_value = "#{show.call(result.first)}#{suffix}"

      if result.size > 1
        last_value = "#{show.call(result.last)}#{suffix}"
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

    class ReduceProductionCooldown < Talent
      include TalentUtility

      def name
        'Reduce production cooldown'
      end

      def display
        values = values_range(data.dig('minmax', 0), show: yield.method(:stat_time))

        "Reduce by #{values} by #{level} levels"
      end
    end

    class Specialization < Talent
      def initialize(...)
        super
        self.ability = Ability::Specialization.new(
          [key.delete_prefix('against_').capitalize])
      end
    end

    Ability::Specialization::List.each do |type|
      const_set("Against#{type.capitalize}", Specialization)
    end

    class ZombieKiller < Talent
      def initialize(...)
        super
        self.ability = Ability::ZombieKiller.new
      end
    end

    class LootMoney < Talent
      def initialize(...)
        super
        self.ability = Ability::LootMoney.new
      end
    end

    class BaseDestroyer < Talent
      def initialize(...)
        super
        self.ability = Ability::BaseDestroyer.new
      end
    end

    class Strengthen < Talent
      include TalentUtility

      def initialize(...)
        super
        self.ability = Ability::Strengthen.new
      end

      def display
        if data['minmax'].size > 1
          display_full
        else
          display_improve
        end
      end

      private

      def display_full
        threshold = data.dig('minmax', 0).map{ |p| 100 - p }
        modifier = data.dig('minmax', 1).map{ |p| p + 100 }

        display_text = ability.display(
          threshold: values_range(threshold, suffix: '%'),
          modifier: values_range(modifier, suffix: '%'))

        "#{display_text} by #{level} levels"
      end

      def display_improve
        values = values_range(data.dig('minmax', 0), suffix: '%')

        "Improve strengthen by #{values} by #{level} levels"
      end
    end

    class Immunity < Talent
      def initialize(...)
        super
        self.ability = Ability::Immunity.new(
          [key.delete_prefix('immune_').capitalize])
      end
    end

    Ability::Immunity::List.each do |type|
      const_set("Immune#{type.capitalize}", Immunity)
    end

    class Resistance < Talent
      include TalentUtility

      def self.set_constants types
        types.each do |type|
          Talent.const_set("Resistant#{type.capitalize}", self)
        end
      end

      def name
        'Resistant to'
      end

      def display
        values = values_range(data.dig('minmax', 0), suffix: '%')

        "Reduce #{type} #{kind} by #{values} by #{level} levels"
      end

      private

      def type
        key[/([a-z]+)\z/, 1]
      end

      def kind
        self.class.name[/([A-Z][a-z]+)\z/, 1].downcase
      end
    end

    class ResistanceDamage < Resistance
      set_constants(%w[wave surge toxic])
    end

    class ResistanceDuration < Resistance
      set_constants(%w[freeze slow weaken curse])
    end

    class ResistanceDistance < Resistance
      set_constants(%w[knockback])
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
