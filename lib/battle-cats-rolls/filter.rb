# frozen_string_literal: true

require_relative 'stat'

module BattleCatsRolls
  module Filter
    class Chain < Struct.new(:cats, :exclude_talents)
      def filter! selected, all_or_any, filter_table
        return if selected.empty?

        cats.select! do |id, cat|
          indicies = cat['stat'].map.with_index do |raw_stat, index|
            if matched = matched_stats[id]
              next unless matched[index]
            end

            abilities = expand_stat(cat, raw_stat, index)
            index if selected.public_send("#{all_or_any}?") do |item|
              case filter = filter_table[item]
              when String, NilClass
                abilities[filter] || abilities[item]
              else
                filter.match?(abilities,
                  Stat.new(id: id, info: cat, index: index))
              end
            end
          end

          matched_stats[id] = indicies
          indicies.any?
        end
      end

      private

      def matched_stats
        @matched_stats ||= {}
      end

      def expand_stat cat, raw_stat, index
        if exclude_talents || index < 2 # 2 is true form, 3 is ultra form
          raw_stat
        else
          raw_stat.merge(cat['talent'] || {}).merge(
            (cat['talent_against'] || []).inject({}) do |result, against|
              result["against_#{against}"] = true
              result
            end
          )
        end
      end
    end

    module LongRange
      def self.match? abilities, stat=nil
        abilities['long_range_0'] && !OmniStrike.match?(abilities, stat)
      end
    end

    module OmniStrike
      def self.match? abilities, stat=nil
        abilities['long_range_offset_0'].to_i < 0
      end
    end

    module FrontStrike
      def self.match? abilities, stat=nil
        !abilities['long_range_0']
      end
    end

    module Single
      def self.match? abilities, stat=nil
        !abilities['area_effect']
      end
    end

    module Backswing
      def self.match? abilities, stat
        stat.push_duration.to_i <= 1
      end
    end

    module HighDPS
      def self.match? abilities, stat
        stat.dps_sum.to_i >= 7500 ||
          stat.attacks_major.any?{ |attack| attack.dps.to_i >= 7500 }
      end
    end

    module VeryHighDPS
      def self.match? abilities, stat
        stat.dps_sum.to_i >= 15000 ||
          stat.attacks_major.any?{ |attack| attack.dps.to_i >= 15000 }
      end
    end

    module HighSingleBlow
      def self.match? abilities, stat
        stat.damage_sum.to_i >= 50000 ||
          stat.attacks_major.any?{ |attack| attack.damage.to_i >= 50000 }
      end
    end

    module VeryHighSingleBlow
      def self.match? abilities, stat
        stat.damage_sum.to_i >= 100000 ||
          stat.attacks_major.any?{ |attack| attack.damage.to_i >= 100000 }
      end
    end

    module HighSpeed
      def self.match? abilities, stat=nil
        abilities['speed'].to_i >= 20
      end
    end

    module VeryHighSpeed
      def self.match? abilities, stat=nil
        abilities['speed'].to_i >= 40
      end
    end

    module HighHealth
      def self.match? abilities, stat
        stat.health >= 100000
      end
    end

    module VeryHighHealth
      def self.match? abilities, stat
        stat.health >= 200000
      end
    end

    module FastProduction
      def self.match? abilities, stat
        case value = stat.production_cooldown
        when Numeric
          value <= 350
        end
      end
    end

    module VeryFastProduction
      def self.match? abilities, stat
        case value = stat.production_cooldown
        when Numeric
          value <= 175
        end
      end
    end

    module Cheap
      def self.match? abilities, stat
        case value = stat.production_cost
        when Numeric
          value <= 1000
        end
      end
    end

    module VeryCheap
      def self.match? abilities, stat
        case value = stat.production_cost
        when Numeric
          value <= 500
        end
      end
    end

    Specialization = {
      'red' => 'against_red',
      'float' => 'against_float',
      'black' => 'against_black',
      'angel' => 'against_angel',
      'alien' => 'against_alien',
      'zombie' => 'against_zombie',
      'aku' => 'against_aku',
      'relic' => 'against_relic',
      'white' => 'against_white',
      'metal' => 'against_metal',
    }.freeze

    Buff = {
      'massive_damage' => nil,
      'insane_damage' => nil,
      'strong' => nil,
    }.freeze

    Resistant = {
      'resistant' => nil,
      'insane_resistant' => nil,
    }.freeze

    Range = {
      'long-range' => LongRange,
      'omni-strike' => OmniStrike,
      'front-strike' => FrontStrike,
    }.freeze

    Area = {
      'area' => 'area_effect',
      'single' => Single,
    }.freeze

    Control = {
      'freeze' => 'freeze_chance',
      'slow' => 'slow_chance',
      'knockback' => 'knockback_chance',
      'weaken' => 'weaken_chance',
      'curse' => 'curse_chance',
    }.freeze

    Immunity = {
      'freeze' => 'immune_freeze',
      'slow' => 'immune_slow',
      'knockback' => 'immune_knockback',
      'warp' => 'immune_warp',
      'weaken' => 'immune_weaken',
      'curse' => 'immune_curse',
      'wave' => 'immune_wave',
      'block_wave' => nil,
      'surge' => 'immune_surge',
      'explosion' => 'immune_explosion',
      'toxic' => 'immune_toxic',
      'bosswave' => 'immune_bosswave',
    }.freeze

    Counter = {
      'critical_strike' => 'critical_chance',
      'metal_killer' => nil,
      'break_barrier' => 'break_barrier_chance',
      'break_shield' => 'break_shield_chance',
      'zombie_killer' => nil,
      'soul_strike' => nil,
      'colossus_slayer' => nil,
      'behemoth_slayer' => nil,
      'sage_slayer' => nil,
      'witch_slayer' => nil,
      'eva_angel_slayer' => nil,
      'base_destroyer' => nil,
    }.freeze

    Combat = {
      'savage_blow' => 'savage_blow_chance',
      'strengthen' => 'strengthen_threshold',
      'wave' => 'wave_chance',
      'mini-wave' => 'wave_mini',
      'surge' => 'surge_chance',
      'mini-surge' => 'surge_mini',
      'counter-surge' => 'counter_surge',
      'explosion' => 'explosion_chance',
      'conjure' => nil,
    }.freeze

    Other = {
      'extra_money' => nil,
      'dodge' => 'dodge_chance',
      'survive' => 'survive_chance',
      'attack_only' => 'against_only',
      'metallic' => nil,
      'kamikaze' => nil,
    }.freeze

    Aspect = {
      'backswing' => Backswing,
      'high_DPS' => HighDPS,
      'very_high_DPS' => VeryHighDPS,
      'high_single_blow' => HighSingleBlow,
      'very_high_single_blow' => VeryHighSingleBlow,
      'high_speed' => HighSpeed,
      'very_high_speed' => VeryHighSpeed,
      'high_health' => HighHealth,
      'very_high_health' => VeryHighHealth,
      'fast_production' => FastProduction,
      'very_fast_production' => VeryFastProduction,
      'cheap' => Cheap,
      'very_cheap' => VeryCheap,
    }.freeze
  end
end
