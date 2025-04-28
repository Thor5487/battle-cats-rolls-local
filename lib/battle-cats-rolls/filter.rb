# frozen_string_literal: true

module BattleCatsRolls
  module Filter
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
      'strong' => nil,
      'massive_damage' => nil,
      'insane_damage' => nil,
      'resistant' => nil,
      'insane_resistant' => nil,
    }.freeze

    Control = {
      'knockback' => 'knockback_chance',
      'freeze' => 'freeze_chance',
      'slow' => 'slow_chance',
      'weaken' => 'weaken_chance',
      'curse' => 'curse_chance',
    }.freeze

    Immunity = {
      'bosswave' => 'immune_bosswave',
      'knockback' => 'immune_knockback',
      'warp' => 'immune_warp',
      'freeze' => 'immune_freeze',
      'slow' => 'immune_slow',
      'weaken' => 'immune_weaken',
      'curse' => 'immune_curse',
      'wave' => 'immune_wave',
      'block_wave' => nil,
      'surge' => 'immune_surge',
      'explosion' => 'immune_explosion',
      'toxic' => 'immune_toxic',
    }.freeze

    Having = {
      'strengthen' => 'strengthen_threshold',
      'conjure' => nil,
      'wave' => 'wave_chance',
      'mini-wave' => 'wave_mini',
      'surge' => 'surge_chance',
      'mini-surge' => 'surge_mini',
      'counter-surge' => 'counter_surge',
      'explosion' => 'explosion_chance',
      'dodge' => 'dodge_chance',
      'survive' => 'survive_chance',
      'extra_money' => nil,
      'savage_blow' => 'savage_blow_chance',
      'critical_strike' => 'critical_chance',
      'metal_killer' => nil,
      'break_barrier' => 'break_barrier_chance',
      'break_shield' => 'break_shield_chance',
      'zombie_killer' => nil,
      'soul_strike' => nil,
      'colossus_slayer' => nil,
      'behemoth_slayer' => nil,
      'sage_slayer' => nil,
      'attack_only' => 'against_only',
      'base_destroyer' => nil,
      'metalic' => 'metal',
      'kamikaze' => nil,
      'witch_slayer' => nil,
      'eva_angel_slayer' => nil,
    }.freeze
  end
end
