# frozen_string_literal: true

module BattleCatsRolls
  module AbilityUtility
    def seconds_range stat_time
      max_time = (duration * treasure_multiplier).floor

      "#{stat_time[duration]} ~ #{highlight(stat_time[max_time])}"
    end

    def seconds stat_time
      highlight(stat_time[duration])
    end

    def percent integer
      highlight("#{integer}%")
    end

    private

    def highlight text
      "<strong>#{text}</strong>"
    end

    def treasure_multiplier
      1.2
    end

    def range_multiplier
      0.25
    end
  end

  class Ability
    class Specialization < Struct.new(:enemies)
      include AbilityUtility

      def self.build_if_available stat
        enemies =
          %w[red float black angel alien zombie aku relic white metal].
            filter_map do |type|
              stat["against_#{type}"] && type.capitalize
            end

        new(enemies) if enemies.any?
      end

      def name
        'Specialized to'
      end

      def display
        @display ||= enemies
      end

      def specialized; true; end
      def effects; false; end
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
        'Deal 150% ~ 180% damage and take 50% ~ 40% damage'
      end

      def specialized; true; end
      def effects; false; end
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
        'Deal 500% ~ 600% damage'
      end

      def specialized; true; end
      def effects; false; end
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
        'Deal 300% ~ 400% damage'
      end

      def specialized; true; end
      def effects; false; end
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
        'Take 16% ~ 14% damage'
      end

      def specialized; true; end
      def effects; false; end
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
        'Take 25% ~ 20% damage'
      end

      def specialized; true; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Knockback < Struct.new(:chance)
      include AbilityUtility

      def self.build_if_available stat
        new(stat['knockback_chance']) if stat['knockback_chance']
      end

      def name
        'Knockback'
      end

      def display
        percent(chance)
      end

      def specialized; true; end
      def effects; true; end
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
        "#{percent(chance)} for #{seconds_range(stat_time)}"
      end

      def specialized; true; end
      def effects; true; end
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
        "#{percent(chance)} for #{seconds_range(stat_time)}"
      end

      def specialized; true; end
      def effects; true; end
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
        "#{percent(chance)} to reduce enemies damage to #{percent(multiplier)} for #{seconds_range(stat_time)}"
      end

      def specialized; true; end
      def effects; true; end
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
        "#{percent(chance)} to invalidate specialization for #{seconds_range(stat_time)}"
      end

      def specialized; true; end
      def effects; true; end
      def index; __LINE__; end
    end

    class Dodge < Struct.new(:chance, :duration)
      include AbilityUtility

      def self.build_if_available stat
        if stat['dodge_chance']
          new(*stat.values_at('dodge_chance', 'dodge_duration'))
        end
      end

      def name
        'Dodge'
      end

      def display &stat_time
        "#{percent(chance)} to become immune to enemies for #{seconds(stat_time)}"
      end

      def specialized; true; end
      def effects; false; end
      def index; __LINE__; end
    end

    class AgainstOnly
      def self.build_if_available stat
        new if stat['against_only']
      end

      def name
        'Attack only'
      end

      def display
        "Only attack specialized enemies or enemy base.<br>\nWhen cursed, only attack the base."
      end

      def specialized; true; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Strengthen < Struct.new(:threshold, :modifier)
      include AbilityUtility

      def self.build_if_available stat
        if stat['strengthen_threshold']
          new(*stat.values_at('strengthen_threshold', 'strengthen_modifier'))
        end
      end

      def name
        'Strengthen'
      end

      def display
        "Deal #{percent(modifier + 100)} damage when health reached #{percent(threshold)}"
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Wave < Struct.new(:chance, :level, :mini)
      include AbilityUtility

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
        "#{percent(chance)} to produce level #{highlight(level)} #{name.downcase} attack"
      end

      def display_short
        "#{percent(chance)} #{name.downcase}"
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end
    end

    class Surge < Struct.new(
      :chance, :level, :mini, :range, :range_offset)
      include AbilityUtility

      def self.build_if_available stat
        if stat['surge_chance']
          new(*stat.values_at(
            'surge_chance', 'surge_level', 'surge_mini',
            'surge_range', 'surge_range_offset'))
        end
      end

      def name
        if mini
          'Mini-surge'
        else
          'Surge'
        end
      end

      def display
        area = highlight("#{area_range.begin} ~ #{area_range.end}")

        "#{percent(chance)} to produce level #{highlight(level)}" \
          " #{name.downcase} attack within #{area}"
      end

      def display_short
        "#{percent(chance)} #{name.downcase}"
      end

      def area_range
        @area_range ||= start..reach
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end

      private

      def start
        (range * range_multiplier).floor
      end

      def reach
        start + (range_offset * range_multiplier).floor
      end
    end

    class CounterSurge
      def self.build_if_available stat
        new if stat['counter_surge']
      end

      def name
        'Counter-surge'
      end

      def display
        'Spawn the same surge with self damage and effects when hit by a surge'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class CriticalStrike < Struct.new(:chance)
      include AbilityUtility

      def self.build_if_available stat
        new(stat['critical_chance']) if stat['critical_chance']
      end

      def name
        'Critical strike'
      end

      def display
        "#{percent(chance)} to deal 200% damage and ignore metal effect"
      end

      def modifier
        100
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end
    end

    class SavageBlow < Struct.new(:chance, :modifier)
      include AbilityUtility

      def self.build_if_available stat
        if stat['savage_blow_chance']
          new(*stat.values_at('savage_blow_chance', 'savage_blow_modifier'))
        end
      end

      def name
        'Savage blow'
      end

      def display
        "#{percent(chance)} to deal #{percent(modifier + 100)} damage"
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end
    end

    class Survive < Struct.new(:chance)
      include AbilityUtility

      def self.build_if_available stat
        new(stat['survive_chance']) if stat['survive_chance']
      end

      def name
        'Survive'
      end

      def display
        "#{percent(chance)} to survive a lethal strike to be knocked back with 1 health"
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class LootMoney
      def self.build_if_available stat
        new if stat['loot_money']
      end

      def name
        'Extra money'
      end

      def display
        'Get double money from defeating enemies'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class BaseDestroyer
      def self.build_if_available stat
        new if stat['base_destroyer']
      end

      def name
        'Base destroyer'
      end

      def display
        'Deal 400% damage to enemy base'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Metal
      def self.build_if_available stat
        new if stat['metal']
      end

      def name
        'Metal'
      end

      def display
        'Take only 1 damage except from critical strikes'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Kamikaze
      def self.build_if_available stat
        new if stat['suicide']
      end

      def name
        'Kamikaze'
      end

      def display
        'It dies from its own attack'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class ZombieKiller
      def self.build_if_available stat
        new if stat['zombie_killer']
      end

      def name
        'Zombie killer'
      end

      def display
        'Final blow prevents zombies from reviving'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class SoulStrike
      def self.build_if_available stat
        new if stat['soul_strike']
      end

      def name
        'Soul strike'
      end

      def display
        'It can attack zombie corpses'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class BreakBarrier < Struct.new(:chance)
      include AbilityUtility

      def self.build_if_available stat
        new (stat['break_barrier_chance']) if stat['break_barrier_chance']
      end

      def name
        'Break barrier'
      end

      def display
        "#{percent(chance)} to break star alien barrier"
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end
    end

    class BreakShield < Struct.new(:chance)
      include AbilityUtility

      def self.build_if_available stat
        new (stat['break_shield_chance']) if stat['break_shield_chance']
      end

      def name
        'Break shield'
      end

      def display
        "#{percent(chance)} to break aku shield"
      end

      def specialized; false; end
      def effects; true; end
      def index; __LINE__; end
    end

    class ColossusSlayer
      def self.build_if_available stat
        new if stat['colossus_killer']
      end

      def name
        'Colossus slayer'
      end

      def display
        'Deal 160% damage to and take 70% damage from colossus'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class BehemohSlayer < Struct.new(:chance, :duration)
      include AbilityUtility

      def self.build_if_available stat
        if stat['behemoth_killer']
          new(*stat.values_at(
            'behemoth_dodge_chance', 'behemoth_dodge_duration'))
        end
      end

      def name
        'Behemoth slayer'
      end

      def display &stat_time
        "Deal 250% and take 60% damage, and #{percent(chance)} to be immune for #{seconds(stat_time)}"
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class SageSlayer
      def self.build_if_available stat
        new if stat['sage_killer']
      end

      def name
        'Sage slayer'
      end

      def display
        'Deal 120% damage, take 50% damage, trigger 100% effects for sages'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class WitchSlayer
      def self.build_if_available stat
        new if stat['witch_killer']
      end

      def name
        'Witch slayer'
      end

      def display
        'Deal 500% damage to and take 10% damage from witches'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class EvaAngelSlayer
      def self.build_if_available stat
        new if stat['eva_angel_killer']
      end

      def name
        'Eva angel slayer'
      end

      def display
        'Deal 500% damage to and take 20% damage from eva angels'
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    class Immunity < Struct.new(:immunity)
      include AbilityUtility

      def self.build_if_available stat
        immunity =
          %w[bosswave knockback warp freeze slow weaken
             toxic curse wave surge].
          filter_map do |effect|
            stat["immune_#{effect}"] && effect.capitalize
          end

        new(immunity) if immunity.any?
      end

      def name
        'Immune to'
      end

      def display
        @immunity ||= immunity
      end

      def specialized; false; end
      def effects; false; end
      def index; __LINE__; end
    end

    def self.build stat
      constants.filter_map do |ability|
        const_get(ability, false).build_if_available(stat)
      end.sort_by(&:index)
    end

    def self.build_if_available stat
    end

    def specialized; false; end
    def effects; false; end
    def index; __LINE__; end
  end
end
