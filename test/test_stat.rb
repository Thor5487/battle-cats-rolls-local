
require 'pork/auto'
require 'battle-cats-rolls/stat'
require 'battle-cats-rolls/route'

describe BattleCatsRolls::Stat do
  BattleCatsRolls::Route.reload_balls

  def lang; 'en'; end
  def level; 30; end
  def index; 0; end
  def sum_no_wave; nil; end
  def dps_no_critical; nil; end
  def stat
    @stat ||= BattleCatsRolls::Stat.new(
      id: id, index: index, level: level,
      sum_no_wave: sum_no_wave,
      dps_no_critical: dps_no_critical,
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

      describe 'but can be disabled' do
        def dps_no_critical; true; end

        would 'return correct DPS' do
          attacks = stat.attacks

          expect(attacks.size).eq 2
          expect(attacks.first.dps.round(3)).eq 3306.522
          expect(attacks.last.dps.round(3)).eq 1780.435
          expect(stat.dps_sum.round(3)).eq 5086.957
        end
      end
    end

    describe 'Lasvoss Reborn' do
      def id; 520; end
      def index; 2; end

      def expected_dps
        14658.683
      end

      copy do
        would 'return correct DPS' do
          attacks = stat.attacks

          expect(attacks.size).eq 1
          expect(attacks.first.dps.round(3)).eq expected_dps
          expect(stat.dps_sum.round(3)).eq expected_dps
        end
      end

      paste

      describe 'but can be disabled' do
        def dps_no_critical; true; end

        def expected_dps
          9161.677
        end

        paste
      end
    end
  end

  describe 'DPS account wave attacks' do
    def lang; 'jp'; end # No DPS data for en

    describe 'Shampoo' do
      def id; 600; end

      def wave_dps
        dps * wave_chance * 0.2 # mini-wave 20% damage
      end

      copy :test do
        would 'have correct dps' do
          attacks = stat.attacks
          expect(attacks.size).eq number_of_attacks * 2

          all_dps = [dps, wave_dps] * number_of_attacks

          expect(stat.attacks.map(&:dps).map(&:round)).eq all_dps.map(&:round)
          expect(stat.dps_sum.round).eq dps_sum(all_dps.sum).round
        end
      end

      copy :account_wave do
        describe 'wave dps' do
          def dps_sum sum
            sum
          end

          paste :test
        end
      end

      copy :discount_wave do
        describe 'no wave dps' do
          def sum_no_wave; true; end

          def dps_sum sum
            sum - wave_dps * number_of_attacks
          end

          paste :test
        end
      end

      describe 'cat form' do
        def number_of_attacks; 2; end
        def dps; 960.616; end
        def wave_chance; 0.5; end

        paste :account_wave
        paste :discount_wave
      end

      describe 'human form' do
        def index; 1; end

        def number_of_attacks; 3; end
        def dps; 1754.140; end
        def wave_chance; 1; end

        paste :account_wave
        paste :discount_wave
      end
    end
  end

  describe '#max_dps_area' do
    def index; 1; end

    copy do
      would 'return correct max DPS area along with mini-wave' do
        expect(stat.max_dps_area).eq area
      end
    end

    describe 'Masked Grandmaster Cat' do
      def id; 353; end
      def index; 2; end
      def area; '255'; end

      paste
    end

    describe 'Mighty Aegis Garu' do
      def id; 586; end
      def area; '-67 ~ 400'; end

      paste
    end

    describe 'Wedding Chronos' do
      def id; 662; end
      def area; '300 ~ 700'; end

      paste
    end

    describe 'King of Destiny Phonoa' do
      def id; 691; end
      def area; '590 ~ 600'; end

      paste
    end
  end
end
