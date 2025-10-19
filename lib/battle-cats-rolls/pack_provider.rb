# frozen_string_literal: true

require_relative 'pack_reader'
require_relative 'provider'

module BattleCatsRolls
  class PackProvider < Struct.new(
    :data_reader, :res_reader, :animation_readers)

    def initialize lang, dir
      local_readers = %w[DataLocal.list resLocal.list].
        map do |list|
          PackReader.new(lang, "#{dir}/#{list}")
        end

      super(*local_readers, new_readers(lang, dir, 'ImageData'))
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

    def skill_acquisition
      data[:skill_acquisition]
    end

    def units
      data[:units]
    end

    def attack_maanims
      @attack_maanims ||= animation_readers.reverse_each.
        inject({}) do |result, reader|
          load_maanims(reader, result)
        end
    end

    def load_maanims reader, init={}
      reader.list_lines.
        grep(/\A\d+_[#{Provider.forms.join}]02\.maanim,\d+,\d+$/).
        inject(init) do |result, line|
          filename, maanim_read = reader.read(line)
          id, form_index =
            Provider.extract_id_and_form_from_maanim_path(filename)

          next result if result.dig(id, form_index)

          maanim = maanim_read.call
          (result[id] ||= [])[form_index] = maanim unless maanim.empty?

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
          (?:GatyaDataSetR1|unitbuy|unit\d+|unitlevel|SkillAcquisition)\.csv)
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
          when 'SkillAcquisition.csv'
            result[:skill_acquisition] = data
          else # unit\d+
            id = filename[/\Aunit(\d+)/, 1].to_i
            (result[:units] ||= {})[id] = data
          end

          result
        end
    end

    def new_readers lang, dir, name
      paths = Dir["#{dir}/*#{name}Server*.list"].sort <<
        "#{dir}/#{name}Local.list"

      paths.map{ |list| PackReader.new(lang, list) }
    end
  end
end
