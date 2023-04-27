
require 'pork/auto'
require 'battle-cats-rolls/stat'
require 'battle-cats-rolls/route'

describe BattleCatsRolls::Stat do
  BattleCatsRolls::Route.reload_balls

  describe 'correct health by correct level multiplier' do
    def stat
      @stat ||= BattleCatsRolls::Stat.new(
        id: id, index: 0, level: level,
        info: BattleCatsRolls::Route.ball_en.cats[id])
    end

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
end
