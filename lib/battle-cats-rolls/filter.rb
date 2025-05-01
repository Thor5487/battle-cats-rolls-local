# frozen_string_literal: true

module BattleCatsRolls
  class Filter < Struct.new(:cats)
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

    def filter! selected, all_or_any, filters
      return if selected.empty?

      cats.select! do |id, cat|
        cat['stat'].find do |stat|
          selected.public_send("#{all_or_any}?") do |item|
            abilities = stat.merge(cat['talent'] || {})
            abilities[filters[item]] || abilities[item]
          end
        end
      end
    end
  end
end
