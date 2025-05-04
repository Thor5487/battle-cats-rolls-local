
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

    expect(ids).not.include?(270) # Baby Gao, front-strike
    expect(ids).include?(319) # Miko Mitama, long-range
    expect(ids).not.include?(780) # Celestial Child Luna, omni-strike
  end

  would 'filter omni-strike without long-range' do
    ids = chain.filter!(['omni-strike'], 'all',
      BattleCatsRolls::Filter::Range).keys

    expect(ids).not.include?(270) # Baby Gao, front-strike
    expect(ids).not.include?(319) # Miko Mitama, long-range
    expect(ids).include?(780) # Celestial Child Luna, omni-strike
  end

  would 'filter front-strike without long-range nor omni-strike' do
    ids = chain.filter!(['front-strike'], 'all',
      BattleCatsRolls::Filter::Range).keys

    expect(ids).include?(270) # Baby Gao, front-strike
    expect(ids).not.include?(319) # Miko Mitama, long-range
    expect(ids).not.include?(780) # Celestial Child Luna, omni-strike
  end

  would 'not filter talents applied to first and second form' do
    chain.filter!(%w[black angel alien], 'all',
      BattleCatsRolls::Filter::Specialization)
    chain.filter!(%w[dodge survive], 'all',
      BattleCatsRolls::Filter::Other)
    ids = chain.cats.keys

    expect(ids).include?(35) # Nekoluga
    expect(ids).not.include?(196) # Mekako Saionji, black only for first form
  end

  would 'not filter across different forms' do
    chain.filter!(['alien'], 'all',
      BattleCatsRolls::Filter::Specialization)
    chain.filter!(['massive_damage'], 'all',
      BattleCatsRolls::Filter::Buff)
    chain.filter!(['resistant'], 'all',
      BattleCatsRolls::Filter::Resistant)
    ids = chain.cats.keys

    expect(ids).not.include?(196) # Mekako Saionji, resistant only in 1st form
    expect(ids).include?(360) # Bora
  end

  would 'not filter across different forms for lugas' do
    chain.filter!(['single'], 'all', BattleCatsRolls::Filter::Area)
    chain.filter!(%w[freeze weaken], 'all', BattleCatsRolls::Filter::Control)
    ids = chain.cats.keys

    expect(ids).not.include?(172) # Balaluga, single only in 1st form
    expect(ids).include?(649) # Lovestruck Lesser Demon
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
