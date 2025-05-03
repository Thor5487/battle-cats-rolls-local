
require 'pork/auto'
require 'battle-cats-rolls/filter'
require 'battle-cats-rolls/crystal_ball'
require 'battle-cats-rolls/route'

describe BattleCatsRolls::Filter do
  BattleCatsRolls::Route.reload_balls

  def ball; BattleCatsRolls::Route.ball_en; end
  def exclude_talents; false; end

  def chain
    @chain ||= BattleCatsRolls::Filter::Chain.new(
      ball.cats.dup, exclude_talents)
  end

  would 'not give Metal Cat when filtering against metal specialization' do
    ids = chain.filter!(['metal'], 'all',
      BattleCatsRolls::Filter::Specialization).keys

    expect(ids).include?(89) # Rope Jump Cat
    expect(ids).not.include?(201) # Metal Cat
  end

  would 'filter against hybrid talents with specialization' do
    ids = chain.filter!(['metal'], 'all',
      BattleCatsRolls::Filter::Specialization).keys

    expect(ids).include?(85) # Megidora, talent, against_metal
    expect(ids).include?(170) # Kubiluga, talent, talent_against: [metal]
    expect(ids).include?(574) # Vega, native, against_metal
  end

  would 'filter both native strengthen and talent strengthen' do
    ids = chain.filter!(['strengthen'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(45) # Lesser Demon Cat, talent, strengthen
    expect(ids).include?(73) # Maeda Keiji, native, strengthen_threshold
  end

  would 'filter both native mini-surge and talent mini-surge' do
    ids = chain.filter!(['mini-surge'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(144) # Nurse Cat, talent, surge_mini
    expect(ids).include?(706) # King of Doom Phono, native, surge_mini
  end

  would 'filter both native mini-wave and talent mini-wave' do
    ids = chain.filter!(['mini-wave'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(137) # Momotaro, talent, wave_mini
    expect(ids).include?(586) # Baby Garu, native, wave_mini
  end

  would 'filter long-range without omni-strike' do
    ids = chain.filter!(['long-range'], 'all',
      BattleCatsRolls::Filter::Range).keys

    expect(ids).not.include?(270) # Baby Gao, simple area
    expect(ids).include?(319) # Miko Mitama, long range
    expect(ids).not.include?(780) # Celestial Child Luna, omni strike
  end

  would 'filter omni-strike without long-range' do
    ids = chain.filter!(['omni-strike'], 'all',
      BattleCatsRolls::Filter::Range).keys

    expect(ids).not.include?(270) # Baby Gao, simple area
    expect(ids).not.include?(319) # Miko Mitama, long range
    expect(ids).include?(780) # Celestial Child Luna, omni strike
  end

  would 'filter front-strike without long-range nor omni-strike' do
    ids = chain.filter!(['front-strike'], 'all',
      BattleCatsRolls::Filter::Range).keys

    expect(ids).include?(270) # Baby Gao, simple area
    expect(ids).not.include?(319) # Miko Mitama, long range
    expect(ids).not.include?(780) # Celestial Child Luna, omni strike
  end

  describe 'exclude_talents option' do
    def exclude_talents; true; end

    would 'filter native strengthen and exclude talent strengthen' do
      ids = chain.filter!(['strengthen'], 'all',
        BattleCatsRolls::Filter::Combat).keys

      expect(ids).not.include?(45) # Lesser Demon Cat, talent, strengthen
      expect(ids).include?(73) # Maeda Keiji, native, strengthen_threshold
    end

    would 'filter native mini-surge and exclude talent mini-surge' do
      ids = chain.filter!(['mini-surge'], 'all',
        BattleCatsRolls::Filter::Combat).keys

      expect(ids).not.include?(144) # Nurse Cat, talent, surge_mini
      expect(ids).include?(706) # King of Doom Phono, native, surge_mini
    end

    would 'filter native mini-wave and exclude talent mini-wave' do
      ids = chain.filter!(['mini-wave'], 'all',
        BattleCatsRolls::Filter::Combat).keys

      expect(ids).not.include?(137) # Momotaro, talent, wave_mini
      expect(ids).include?(586) # Baby Garu, native, wave_mini
    end

    would 'filter native specialization and exclude talent' do
      ids = chain.filter!(['metal'], 'all',
        BattleCatsRolls::Filter::Specialization).keys

      expect(ids).not.include?(85) # Megidora, talent, against_metal
      expect(ids).not.include?(170) # Kubiluga, talent, talent_against: [metal]
      expect(ids).include?(574) # Vega, native, against_metal
    end
  end
end
