# frozen_string_literal: true

module BattleCatsRolls
  class Stat < Struct.new(
    :id, :name, :desc, :stat, :level, keyword_init: true)
    class Attack < Struct.new(
      :stat, :damage, :long_range, :long_range_offset,
      :apply_effects, :duration, keyword_init: true)

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

      def apply_effects
        @apply_effects ||= if super == 1 || stat.attacks.size <= 1
          'Yes'
        else
          'No'
        end
      end

      def dps
        @dps ||= stat.attack_interval &&
          ((damage.to_f / stat.attack_interval) * stat.fps).round
      end
    end

    class Ability
      class Against < Struct.new(:enemies)
        def self.build_if_available stat
          enemies =
            %w[red floating black angel alien zombie aku relic white metal].
              filter_map do |type|
                stat["against_#{type}"] && type.capitalize
              end

          new(enemies) if enemies.any?
        end

        def name
          'Specialization'
        end

        def display
          @display ||= enemies.join(', ')
        end
      end

      class Strong
        def self.build_if_available stat
          new if stat['strong']
        end

        def name
          'Strong'
        end

        def display
          'Deal 150%~180% damage and take 50%~40% damage<br>against specialized enemies'
        end
      end

      class InsaneDamage
        def self.build_if_available stat
          new if stat['insane_damage']
        end

        def name
          'Insane damage'
        end

        def display
          'Deal 500%~600% damage against specialized enemies'
        end
      end

      class MassiveDamage
        def self.build_if_available stat
          new if stat['massive_damage']
        end

        def name
          'Massive damage'
        end

        def display
          'Deal 300% ~ 400% damage against specialized enemies'
        end
      end

      class InsaneResistant
        def self.build_if_available stat
          new if stat['insane_resistant']
        end

        def name
          'Insane resistant'
        end

        def display
          'Take 16% ~ 14% damage from specialized enemies'
        end
      end

      class Resistant
        def self.build_if_available stat
          new if stat['resistant']
        end

        def name
          'Resistant'
        end

        def display
          'Take 25% ~ 20% damage from specialized enemies'
        end
      end

      class Knockback < Struct.new(:chance)
        def self.build_if_available stat
          new(stat['knockback_chance']) if stat['knockback_chance']
        end

        def name
          'Knockback'
        end

        def display
          "#{chance}%"
        end
      end

      class Freeze < Struct.new(:chance, :duration)
        def self.build_if_available stat
          if stat['freeze_chance']
            new(*stat.values_at('freeze_chance', 'freeze_duration'))
          end
        end

        def name
          'Freeze'
        end

        def display
          "#{chance}% for #{yield(duration)}"
        end
      end

      class Slow < Struct.new(:chance, :duration)
        def self.build_if_available stat
          if stat['slow_chance']
            new(*stat.values_at('slow_chance', 'slow_duration'))
          end
        end

        def name
          'Slow'
        end

        def display
          "#{chance}% for #{yield(duration)}"
        end
      end

      class Weaken < Struct.new(:chance, :duration, :multiplier)
        def self.build_if_available stat
          if stat['weaken_chance']
            new(*stat.values_at(
              'weaken_chance', 'weaken_duration', 'weaken_multiplier'))
          end
        end

        def name
          'Weaken'
        end

        def display
          "#{chance}% to reduce specialized enemies damage to #{multiplier}% for #{yield(duration)}"
        end
      end

      class Curse < Struct.new(:chance, :duration)
        def self.build_if_available stat
          if stat['curse_chance']
            new(*stat.values_at('curse_chance', 'curse_duration'))
          end
        end

        def name
          'Curse'
        end

        def display
          "#{chance}% to invalidate specialization for #{yield(duration)}"
        end
      end

      class Dodge < Ability
      end

      class Strengthen < Struct.new(:threshold, :modifier)
        def self.build_if_available stat
          if stat['strengthen_threshold']
            new(*stat.values_at('strengthen_threshold', 'strengthen_modifier'))
          end
        end

        def name
          'Strengthen'
        end

        def display
          "Deal #{modifier + 100}% damage when health reached #{threshold}%"
        end
      end

      class Wave < Ability
      end

      class Surge < Ability
      end

      class CriticalStrike < Ability
      end

      class SavageBlow < Ability
      end

      class Survival < Ability
      end

      class LootMoney < Ability
      end

      class BaseDestroyer < Ability
      end

      class Metal < Ability
      end

      class Kamikaze < Ability
      end

      class ZombieKiller < Ability
      end

      class SoulStrike < Ability
      end

      class BreakBarrier < Ability
      end

      class BreakShield < Ability
      end

      class ColossusKiller < Ability
      end

      class BehemohKiller < Ability
      end

      class WitchKiller < Ability
      end

      class EvaAngelKiller < Ability
      end

      class Immunity < Struct.new(:immunity)
        def self.build_if_available stat
          immunity =
            %w[knockback warp freeze slow weaken toxic curse wave surge].
            filter_map do |effect|
              stat["immune_#{effect}"] && effect.capitalize
            end

          new(immunity) if immunity.any?
        end

        def name
          'Immunity'
        end

        def display
          @immunity ||= immunity.join(', ')
        end
      end

      def self.build stat
        constants.filter_map do |ability|
          const_get(ability, false).build_if_available(stat)
        end
      end

      def self.build_if_available stat
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
      @production_cooldown ||= begin
        minimal_cooldown = 60
        reduction_from_blue_orbs_and_treasures = 264

        [
          minimal_cooldown,
          (stat['production_cooldown'] * time_multiplier) -
            reduction_from_blue_orbs_and_treasures
        ].max
      end
    end

    def rush_duration
      @rush_duration ||= attack_duration &&
        attack_interval - attack_duration
    end

    def attack_interval
      @attack_interval ||= attack_duration &&
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
      attacks.any?{ |atk| atk.area_range.kind_of?(Range) }
    end

    def max_dps
      @max_dps ||= attack_interval &&
        ((max_damage.to_f / attack_interval) * fps).round
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
          apply_effects: apply_effects(n), duration: duration(n))
      end
    end

    def abilities
      @abilities ||= Ability.build(stat)
    end

    private

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

    def apply_effects n=0
      stat["apply_effects_#{n}"]
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

    def time_multiplier
      2
    end

    def chapter2_cost_multiplier
      1.5
    end

    def level_multiplier
      @level_multiplier ||= 1 + 0.2 * (level - 1)
    end
  end
end
