
require 'pork/auto'
require 'battle-cats-rolls/filter'
require 'battle-cats-rolls/crystal_ball'
require 'battle-cats-rolls/route'

describe BattleCatsRolls::Filter do
  BattleCatsRolls::Route.reload_balls

  def ball
    BattleCatsRolls::Route.ball_en
  end

  def filter
    @filter ||= BattleCatsRolls::Filter.new(ball.cats.dup)
  end

  would 'not give Metal Cat when filtering against metal specialization' do
    ids = filter.filter!(['metal'], 'all',
      BattleCatsRolls::Filter::Specialization).keys

    expect(ids).include?(89) # Rope Jump Cat
    expect(ids).not.include?(201) # Metal Cat
  end

  would 'filter both native strengthen and talent strengthen' do
    ids = filter.filter!(['strengthen'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(45) # Lesser Demon Cat, talent, strengthen
    expect(ids).include?(73) # Maeda Keiji, native, strengthen_threshold
  end

  would 'filter both native mini-surge and talent mini-surge' do
    ids = filter.filter!(['mini-surge'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(144) # Nurse Cat, talent, surge_mini
    expect(ids).include?(706) # King of Doom Phono, native, surge_mini
  end

  would 'filter both native mini-wave and talent mini-wave' do
    ids = filter.filter!(['mini-wave'], 'all',
      BattleCatsRolls::Filter::Combat).keys

    expect(ids).include?(137) # Momotaro, talent, wave_mini
    expect(ids).include?(586) # Baby Garu, native, wave_mini
  end
end
