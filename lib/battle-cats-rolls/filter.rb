# frozen_string_literal: true

module BattleCatsRolls
  module Filter
    class Chain < Struct.new(:cats, :exclude_talents)
      def filter! selected, all_or_any, filter_table
        return if selected.empty?

        cats.select! do |id, cat|
          cat['stat'].find.with_index do |stat, index|
            abilities = expand_stat(cat, stat, index)
            selected.public_send("#{all_or_any}?") do |item|
              case filter = filter_table[item]
              when String, NilClass
                abilities[filter] || abilities[item]
              else
                filter.match?(abilities)
              end
            end
          end
        end
      end

      private

      def expand_stat cat, stat, index
        if exclude_talents || index < 2 # 2 is true form, 3 is ultra form
          stat
        else
          stat.merge(cat['talent'] || {}).merge(
            (cat['talent_against'] || []).inject({}) do |result, against|
              result["against_#{against}"] = true
              result
            end
          )
        end
      end
    end

    module LongRange
      def self.match? abilities
        abilities['long_range_0'] && !OmniStrike.match?(abilities)
      end
    end

    module OmniStrike
      def self.match? abilities
        abilities['long_range_offset_0'].to_i < 0
      end
    end

    module FrontStrike
      def self.match? abilities
        !abilities['long_range_0']
      end
    end

    module Single
      def self.match? abilities
        !abilities['area_effect']
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
  end
end
