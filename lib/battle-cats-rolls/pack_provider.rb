# frozen_string_literal: true

require_relative 'pack_reader'
require_relative 'provider'

module BattleCatsRolls
  class PackProvider < Struct.new(:data_reader, :res_reader, :animation_reader)
    def initialize lang, dir
      super(
        PackReader.new(lang, "#{dir}/DataLocal.list"),
        PackReader.new(lang, "#{dir}/resLocal.list"),
        PackReader.new(lang, "#{dir}/ImageDataLocal.list"))
    end

    def gacha
      data[:gacha]
    end

    def gacha_option
      data[:gacha_option]
    end

    def unitbuy
      data[:unitbuy]
    end

    def unitlevel
      data[:unitlevel]
    end

    def units
      data[:units]
    end

    def attack_maanims
      @attack_maanims ||= animation_reader.list_lines.
        grep(/\A\d+_[fcs]02\.maanim,\d+,\d+$/).
        inject({}) do |result, line|
          filename, maanim = animation_reader.read_eagerly(line)
          id, form_index =
            Provider.extract_id_and_form_from_maanim_path(filename)

          (result[id] ||= [])[form_index] = maanim
          result
        end
    end

    def res
      @res ||= res_reader.list_lines.
        grep(/\AUnit_Explanation\d+_\w+\.csv,\d+,\d+$/).
        inject({}) do |result, line|
          result.store(*res_reader.read_eagerly(line))
          result
        end
    end

    private

    def data
      @data ||= data_reader.list_lines.
        grep(/\A
          (?:GatyaData_Option_SetR\.tsv|
          (?:GatyaDataSetR1|unitbuy|unit\d+|unitlevel)\.csv)
          ,\d+,\d+$/x).
        inject({}) do |result, line|
          filename, data = data_reader.read_eagerly(line)

          case filename
          when 'GatyaData_Option_SetR.tsv'
            result[:gacha_option] = data
          when 'GatyaDataSetR1.csv'
            result[:gacha] = data
          when 'unitbuy.csv'
            result[:unitbuy] = data
          when 'unitlevel.csv'
            result[:unitlevel] = data
          else # unit\d+
            id = filename[/\Aunit(\d+)/, 1].to_i
            (result[:units] ||= {})[id] = data
          end

          result
        end
    end
  end
end
