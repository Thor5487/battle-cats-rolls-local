# frozen_string_literal: true

require_relative 'ability'

module BattleCatsRolls
  class Stat < Struct.new(
    :id, :info, :index, :level,
    :dps_no_critical, keyword_init: true)
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

      def display_effects
        @display_effects ||= if trigger_effects?
          effects.map(&:name).join(', ')
        else
          '-'
        end
      end

      def dps
        @dps ||= if stat.kamikaze?
          '-'
        elsif stat.attack_cycle
          raw_dps = (damage.to_f / stat.attack_cycle) * stat.fps

          if stat.dps_no_critical
            raw_dps
          else
            account_critical(raw_dps)
          end
        end
      end

      private

      def trigger_effects?
        # Older cats with single attack might not be marked with triggering
        # effects, but they do according to the game. For example,
        # Apple Cat (id=40) has no trigger effects but it does trigger effect!
        trigger_effects == 1 || stat.attacks.size <= 1
      end

      def effects
        @effects ||= if trigger_effects?
          stat.effects
        else
          []
        end
      end

      def critical_effects
        @critical_effects ||= effects.select do |eff|
          case eff
          when Ability::CriticalStrike, Ability::SavageBlow
            true
          end
        end
      end

      def account_critical raw_dps
        critical_effects.inject(raw_dps) do |result, critical|
          result *
            (1 + (critical.modifier / 100.0) * (critical.chance / 100.0))
        end
      end
    end

    def name
      info.dig('name', index)
    end

    def desc
      info.dig('desc', index)
    end

    def stat
      info.dig('stat', index)
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
        attack_cycle - attack_duration
    end

    def attack_cycle
      @attack_cycle ||= attack_duration &&
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

    def damage_sum
      @damage_sum ||= attacks.sum(&:damage)
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

    def effects
      @effects ||= abilities.flat_map do |(_, abis)|
        abis.select(&:effects)
      end
    end

    def dps_sum
      @dps_sum ||= if kamikaze?
        '-'
      elsif attack_cycle
        attacks.sum(&:dps)
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

    def level_multiplier
      @level_multiplier ||= begin
        growth = info['growth'].map{ |percent| percent / 100.0 }
        reminder = level % 10
        steps = level / 10
        1 + # base multiplier
          (growth[0...steps].sum * 10) + # sum of every 10 levels
          ((growth[steps] || 0) * reminder) -
          growth.first # subtract the first level because level starts at 1
      end
    end
  end
end
