# frozen_string_literal: true

module BattleCatsRolls
  class ExtractProvider < Struct.new(:dir)
    def gacha
      @gacha ||= File.binread("#{dir}/DataLocal.pack/GatyaDataSetR1.csv")
    end

    def unitbuy
      @unitbuy ||= File.binread("#{dir}/DataLocal.pack/unitbuy.csv")
    end

    def units
      @units ||= Dir["#{dir}/DataLocal.pack/unit*.csv"].
        inject({}) do |result, path|
          # Some files match the glob pattern but not regexp pattern
          if id = path[/unit(\d+)\.csv\z/, 1]
            result[id.to_i] = File.binread(path)
          end

          result
        end
    end

    def res
      @res ||= Dir["#{dir}/resLocal.pack/Unit_Explanation*_*.csv"].
        inject({}) do |result, path|
          result[File.basename(path)] = File.read(path)
          result
        end
    end
  end
end
