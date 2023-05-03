
require 'pork/auto'
require 'battle-cats-rolls/stat'
require 'battle-cats-rolls/route'

describe BattleCatsRolls::Stat do
  BattleCatsRolls::Route.reload_balls

  def lang; 'en'; end
  def level; 30; end
  def index; 0; end
  def stat
    @stat ||= BattleCatsRolls::Stat.new(
      id: id, index: index, level: level,
      info: BattleCatsRolls::Route.public_send("ball_#{lang}").cats[id])
  end

  describe 'cats without triggering effects can trigger effects' do
    def id; 40; end

    would 'trigger effects even when it does not have it' do
      attack = stat.attacks.first

      expect(stat.attacks.size).eq 1
      expect(attack.trigger_effects).eq nil
      expect(attack.display_effects).eq 'Freeze'
    end
  end

  describe 'correct health by correct level multiplier' do
    copy :check_health do
      would 'be correct' do
        expect(stat.health).eq health
      end
    end

    describe 'Gacha Cat' do
      def id; 559; end
      def level; 50; end
      def health; 153000; end
      paste :check_health
    end

    describe 'Pogo Cat' do
      def id; 38; end
      def level; 130; end
      def health; 14100; end
      paste :check_health
    end

    describe 'Crazed Titan Cat' do
      def id; 100; end
      def level; 30; end
      def health; 52200; end
      paste :check_health
    end

    describe 'Bahamut Cat' do
      def id; 26; end
      def level; 50; end
      def health; 33000; end
      paste :check_health
    end
  end

  describe 'DPS accounts critical strike and savage blow' do
    def lang; 'tw'; end # No DPS data for en

    describe 'Kyosaka Nanaho' do
      def id; 545; end
      def level; 35; end # This level can test rounding error

      would 'return correct DPS' do
        attacks = stat.attacks

        expect(attacks.size).eq 2
        expect(attacks.first.dps.round(3)).eq 3306.522
        expect(attacks.last.dps.round(3)).eq 2670.652 # 50% critical strike
        expect(stat.dps_sum.round(3)).eq 5977.174 # Not 5978
      end
    end

    describe 'Lasvoss Reborn' do
      def id; 520; end
      def index; 2; end

      would 'return correct DPS' do
        attacks = stat.attacks
        expected_dps = 14658.683

        expect(attacks.size).eq 1
        expect(attacks.first.dps.round(3)).eq expected_dps
        expect(stat.dps_sum.round(3)).eq expected_dps
      end
    end
  end
end
