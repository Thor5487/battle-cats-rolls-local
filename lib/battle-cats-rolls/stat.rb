# frozen_string_literal: true

require_relative 'ability'

module BattleCatsRolls
  class Stat < Struct.new(
    :id, :name, :desc, :stat, :level, keyword_init: true)
    class Attack < Struct.new(
      :stat, :damage, :long_range, :long_range_offset,
      :trigger_effects, :duration, keyword_init: true)

      def area
        @area ||=
          case area_range
          when Range
            "#{area_range.begin} ~ #{area_range.end}"
          else
            area_range
          end
      end

      def area_range
        @area_range ||= if long_range
          reach = long_range + long_range_offset
          from, to = [long_range, reach].sort
          from..to
        else
          stat.range
        end
      end

      def trigger_effects
        @trigger_effects ||= if super == 1 || stat.attacks.size <= 1
          'Yes'
        else
          'No'
        end
      end

      def dps
        @dps ||= if stat.kamikaze?
          '-'
        elsif stat.damage_interval
          ((damage.to_f / stat.damage_interval) * stat.fps).round
        end
      end
    end

    def fps
      30
    end

    def health
      @health ||=
        (stat['health'] * treasure_multiplier * level_multiplier).round
    end

    def knockbacks
      stat['knockbacks']
    end

    def speed
      stat['speed']
    end

    def production_cost
      @production_cost ||= (stat['cost'] * chapter2_cost_multiplier).floor
    end

    def production_cooldown
      @production_cooldown ||= [
        minimal_cooldown,
        (stat['production_cooldown'] * time_multiplier) -
          reduction_from_blue_orbs_and_treasures
      ].max
    end

    def rush_duration
      @rush_duration ||= attack_duration &&
        damage_interval - attack_duration
    end

    def damage_interval
      @damage_interval ||= attack_duration &&
        [
          attack_duration,
          attacks.sum(&:duration) + attack_cooldown
        ].max
    end

    def attack_duration
      stat['attack_duration']
    end

    def attack_cooldown
      @attack_cooldown ||= stat['attack_cooldown'].to_i * time_multiplier
    end

    def max_damage
      @max_damage ||= attacks.sum(&:damage)
    end

    def range
      stat['range']
    end

    def area_type
      if stat['area_effect']
        'Area'
      else
        'Single'
      end
    end

    def long_range?
      @long_range ||= attacks.any?{ |atk| atk.area_range.kind_of?(Range) }
    end

    def kamikaze?
      @kamikaze ||= generic_abilities.any? do |ability|
        ability.kind_of?(Ability::Kamikaze)
      end
    end

    def max_dps
      @max_dps ||= if kamikaze?
        '-'
      elsif damage_interval
        ((max_damage.to_f / damage_interval) * fps).round
      end
    end

    def max_dps_area
      @max_dps_area ||= if long_range?
        intersected = attacks.map(&:area_range).inject do |result, range|
          [result.begin, range.begin].max..[result.end, range.end].min
        end

        if intersected.any?
          "#{intersected.begin} ~ #{intersected.end}"
        else
          'None'
        end
      elsif stat['area_effect']
        range
      else
        'Single'
      end
    end

    def attacks
      @attacks ||= 3.times.filter_map do |n|
        next unless value = damage(n)

        Attack.new(stat: self, damage: value,
          long_range: long_range(n), long_range_offset: long_range_offset(n),
          trigger_effects: trigger_effects(n), duration: duration(n))
      end
    end

    def specialized_abilities
      @specialized_abilities ||= abilities[true] || []
    end

    def generic_abilities
      @generic_abilities ||= abilities[false] || []
    end

    private

    def abilities
      @abilities ||= Ability.build(stat).group_by(&:specialized)
    end

    def damage n=0
      value = stat["damage_#{n}"]

      (value * treasure_multiplier * level_multiplier).round if value
    end

    def long_range n=0
      attack_stat(__method__, n)
    end

    def long_range_offset n=0
      attack_stat(__method__, n)
    end

    def trigger_effects n=0
      stat["trigger_effects_#{n}"]
    end

    def duration n=0
      prefix = 'attack_time_'

      if n == 0
        stat["#{prefix}#{n}"]
      else
        stat["#{prefix}#{n}"] - stat["#{prefix}#{n - 1}"]
      end
    end

    def attack_stat name, n=0
      key = "#{name}_#{n}"

      if n <= 0
        stat[key]
      else
        stat[key] || attack_stat(name, n - 1)
      end
    end

    def treasure_multiplier
      2.5
    end

    def chapter2_cost_multiplier
      1.5
    end

    def time_multiplier
      2
    end

    def minimal_cooldown
      60
    end

    def reduction_from_blue_orbs_and_treasures
      264
    end

    # checkout unitlevel.csv
    def level_multiplier
      @level_multiplier ||= 1 + 0.2 * (level - 1)
    end
  end
end
