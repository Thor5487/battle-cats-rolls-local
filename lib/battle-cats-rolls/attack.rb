# frozen_string_literal: true

module BattleCatsRolls
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

    def effects
      @effects ||= if trigger_effects?
        stat.effects
      else
        []
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
      trigger_effects == 1 || stat.single_damage?
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

  class WaveAttack < Attack
    def area
      area_range.end # Display this in a simple way
    end

    def area_range
      # Use range because it might need to work with long range
      @area_range ||= self.begin..self.begin + width +
        wave_step * (stat.wave_effect.level - 1)
    end

    def damage
      if stat.wave_effect.mini
        (super * mini_damage_multiplier).round
      else
        super
      end
    end

    def dps
      @dps ||= if stat.kamikaze?
        super
      elsif stat.attack_cycle
        if stat.dps_no_wave
          0
        else
          account_chance(super)
        end
      end
    end

    def effects
      @effects ||= super.reject do |eff|
        case eff
        when Ability::Wave, Ability::Surge
          true
        end
      end
    end

    private

    def wave_step
      (width * next_position_multiplier).round
    end

    def account_chance raw_dps
      raw_dps * stat.wave_effect.chance / 100.0
    end

    def mini_damage_multiplier
      0.2
    end

    def width
      400
    end

    def begin
      -67
    end

    def next_position_multiplier
      0.5
    end
  end
end
