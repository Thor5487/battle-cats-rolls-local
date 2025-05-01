
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
    cats = filter.filter!(['metal'], 'all',
      BattleCatsRolls::Filter::Specialization)

    expect(cats.keys).not.include?(201)
  end
end
