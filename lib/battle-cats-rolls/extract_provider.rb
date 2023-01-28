# frozen_string_literal: true

require_relative 'provider'

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

    def attack_maanims
      @attack_maanims ||= Dir["#{dir}/ImageDataLocal.pack/*{f,c,s}02.maanim"].
        inject({}) do |result, path|
          id, form_index = Provider.extract_id_and_form_from_maanim_path(path)
          (result[id] ||= [])[form_index] = File.binread(path)
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
