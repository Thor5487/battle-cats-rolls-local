# frozen_string_literal: true

module BattleCatsRolls
  module AbilityUtility
    def duration_range stat_time
      "#{stat_time[duration]} ~ #{stat_time[(duration * treasure_multiplier).floor]}"
    end

    def treasure_multiplier
      1.2
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

      def index; __LINE__; end
    end

    class Strong
      def self.build_if_available stat
        new if stat['strong']
      end

      def name
        'Strong'
      end

      def display
        'Deal 150% ~ 180% damage and take 50% ~ 40% damage<br>against and from specialized enemies'
      end

      def index; __LINE__; end
    end

    class InsaneDamage
      def self.build_if_available stat
        new if stat['insane_damage']
      end

      def name
        'Insane damage'
      end

      def display
        'Deal 500% ~ 600% damage against specialized enemies'
      end

      def index; __LINE__; end
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

      def index; __LINE__; end
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

      def index; __LINE__; end
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

      def index; __LINE__; end
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

      def index; __LINE__; end
    end

    class Freeze < Struct.new(:chance, :duration)
      include AbilityUtility

      def self.build_if_available stat
        if stat['freeze_chance']
          new(*stat.values_at('freeze_chance', 'freeze_duration'))
        end
      end

      def name
        'Freeze'
      end

      def display &stat_time
        "#{chance}% for #{duration_range(stat_time)}"
      end

      def index; __LINE__; end
    end

    class Slow < Struct.new(:chance, :duration)
      include AbilityUtility

      def self.build_if_available stat
        if stat['slow_chance']
          new(*stat.values_at('slow_chance', 'slow_duration'))
        end
      end

      def name
        'Slow'
      end

      def display &stat_time
        "#{chance}% for #{duration_range(stat_time)}"
      end

      def index; __LINE__; end
    end

    class Weaken < Struct.new(:chance, :duration, :multiplier)
      include AbilityUtility

      def self.build_if_available stat
        if stat['weaken_chance']
          new(*stat.values_at(
            'weaken_chance', 'weaken_duration', 'weaken_multiplier'))
        end
      end

      def name
        'Weaken'
      end

      def display &stat_time
        "#{chance}% to reduce specialized enemies damage to #{multiplier}% for #{duration_range(stat_time)}"
      end

      def index; __LINE__; end
    end

    class Curse < Struct.new(:chance, :duration)
      include AbilityUtility

      def self.build_if_available stat
        if stat['curse_chance']
          new(*stat.values_at('curse_chance', 'curse_duration'))
        end
      end

      def name
        'Curse'
      end

      def display &stat_time
        "#{chance}% to invalidate specialization for #{duration_range(stat_time)}"
      end

      def index; __LINE__; end
    end

    class Dodge < Struct.new(:chance, :duration)
      def self.build_if_available stat
        if stat['dodge_chance']
          new(*stat.values_at('dodge_chance', 'dodge_duration'))
        end
      end

      def name
        'Dodge'
      end

      def display
        "#{chance}% to become immune to specialized enemies for #{yield(duration)}"
      end

      def index; __LINE__; end
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

      def index; __LINE__; end
    end

    class Wave < Struct.new(:chance, :level, :mini)
      def self.build_if_available stat
        if stat['wave_chance']
          new(*stat.values_at(
            'wave_chance', 'wave_level', 'wave_mini'))
        end
      end

      def name
        if mini
          'Mini-wave'
        else
          'Wave'
        end
      end

      def display
        "#{chance}% to produce level #{level} #{name.downcase} attack"
      end

      def index; __LINE__; end
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

      def index; __LINE__; end
    end

    def self.build stat
      constants.filter_map do |ability|
        const_get(ability, false).build_if_available(stat)
      end.sort_by(&:index)
    end

    def self.build_if_available stat
    end

    def index; __LINE__; end
  end
end
