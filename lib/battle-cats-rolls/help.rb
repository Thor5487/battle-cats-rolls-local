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

    def lookup_cat_data
      @lookup_cat_data ||= [[
        fake_cat(319, 'Miko Mitama', 1, 0),
        fake_cat(-1, 'Cat', 1, 1)
      ]]
    end

    def guaranteed_tracks
      @guaranteed_tracks ||= begin
        tracks = fake_tracks.map(&:dup)

        fake_1AG = fake_cat(-1, '(1A guaranteed uber)', 1, 0)
        fake_1AG.next = tracks.dig(10, 1)
        tracks[0][0] = tracks.dig(0, 0).new_with(guaranteed: fake_1AG)

        fake_1BG = fake_cat(-1, '(1B guaranteed uber)', 1, 1)
        fake_1BG.next = tracks.dig(11, 0)
        tracks[0][1] = tracks.dig(0, 1).new_with(guaranteed: fake_1BG)

        tracks
      end
    end

    def dupe_rare_track
      @dupe_rare_track ||= begin
        tracks = read_the_tracks.map(&:dup)

        tracks[2][0] = fake_cat(148, 'Tin Cat', 3, 0)
        tracks[3][0] = fake_cat(148, 'Tin Cat', 4, 0,
          rerolled: fake_cat(38, 'Pogo Cat', 4, 0,
            next: tracks.dig(4, 1)))

        tracks
      end
    end

    def pick cats, sequence, track, guaranteed=false
      result = cats.map(&:dup)

      if guaranteed
        index = sequence - 1
        index_end = sequence + 9

        pick_sequence(result, index_end, track, :picked_consecutively)

        dup_modify(result, index, track, guaranteed:
          result.dig(index, track).guaranteed.
            new_with(picked_label: :picked_consecutively))

        dup_modify(result, index_end + track ^ 0, track ^ 1,
          picked_label: :next_position)
      else
        pick_sequence(result, sequence, track, :picked)

        if rerolled = result.dig(sequence - 1, track).rerolled
          next_index = rerolled.next.sequence - 1
          next_track = track ^ 1
          dup_modify(result, next_index, next_track,
            picked_label: :next_position)
        else
          dup_modify(result, sequence, track, picked_label: :next_position)
        end
      end

      result
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
          name = "(#{sequence}#{track_label} #{rarity_label} cat)"
          cat = fake_cat(-1, name, sequence, track)
          cat.rarity_label = rarity_label
          cat
        end
      end.transpose
    end

    def fake_cat id, name, sequence, track, **args
      Cat.new(
        id: id, info: {'name' => [name]},
        sequence: sequence, track: track,
        **args)
    end

    def pick_sequence result, sequence, track, label
      (0...sequence).each do |index|
        if rerolled = result.dig(index, track).rerolled
          dup_modify(result, index, track,
            rerolled: rerolled.new_with(picked_label: label))
        else
          dup_modify(result, index, track, picked_label: label)
        end
      end
    end

    def dup_modify result, index, track, **args
      result[index][track] = result.dig(index, track).new_with(**args)
    end
  end
end
