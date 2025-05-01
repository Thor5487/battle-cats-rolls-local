
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

    expect(ids).not.include?(201) # Metal Cat
  end

  would 'filter both native strengthen and talent strengthen' do
    ids = filter.filter!(['strengthen'], 'all',
      BattleCatsRolls::Filter::Having).keys

    expect(ids).include?(45) # Lesser Demon Cat, talent, strengthen
    expect(ids).include?(73) # Maeda Keiji, native, strengthen_threshold
  end
end
