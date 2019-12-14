# frozen_string_literal: true

require_relative 'cat'
require_relative 'gacha'

module BattleCatsRolls
  class Help
    def read_the_tracks
      @read_the_tracks ||= fake_tracks.first(5)
    end

    def advance_the_tracks
      @advance_the_tracks ||=
        read_the_tracks.drop(2).
          map{ |cs| cs.map{ |c| c.new_with(sequence: c.sequence - 2) }}
    end

    def swap_the_tracks
      @swap_the_tracks ||=
        advance_the_tracks.map do |(a, b)|
          [b.new_with(track: 0), a.new_with(track: 1)]
        end
    end

    def lookup_cat_data gacha
      @lookup_cat_data ||= [[
        fake_cat(
          319, gacha.pool.dig_cat(Cat::Uber, 319, 'name', 0), 1, 0),
        fake_cat(-1, 'Cat', 1, 1)
      ]]
    end

    def guaranteed_tracks
      @guaranteed_tracks ||= begin
        tracks = fake_tracks.map(&:dup)
        tracks[0][0] = tracks.dig(0, 0).
          new_with(guaranteed: fake_cat(-1, '1A guaranteed uber', 1, 0))
        tracks[0][1] = tracks.dig(0, 1).
          new_with(guaranteed: fake_cat(-1, '1B guaranteed uber', 1, 1))
        tracks
      end
    end

    private

    def fake_tracks
      @fake_tracks ||= [
        %i[rare supa rare rare supa supa rare uber supa rare legend rare],
        %i[supa rare uber supa rare rare supa rare rare supa rare uber]
      ].map.with_index do |column, track|
        column.map.with_index do |rarity_label, index|
          sequence = index + 1
          track_label = (track + 'A'.ord).chr
          name = "#{sequence}#{track_label} #{rarity_label} cat"
          cat = fake_cat(-1, name, sequence, track)
          cat.rarity_label = rarity_label
          cat
        end
      end.transpose
    end

    def fake_cat id, name, sequence, track
      Cat.new(
        id: id, info: {'name' => [name]},
        sequence: sequence, track: track)
    end
  end
end
