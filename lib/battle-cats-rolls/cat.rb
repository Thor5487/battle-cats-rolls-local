# frozen_string_literal: true

module BattleCatsRolls
  class Cat < Struct.new(
    :id, :info,
    :rarity, :rarity_fruit, :score,
    :slot, :slot_fruit,
    :sequence, :track, :guaranteed,
    :rerolled, :steps, :next,
    :rarity_label, :picked_label,
    keyword_init: true)

    Rare   = 2
    Supa   = 3
    Uber   = 4
    Legend = 5

    def name
      info.dig('name', 0)
    end

    def pick_name index
      info.dig('name', index) || pick_name(index - 1) if index >= 0
    end

    def pick_title index
      picked_name = pick_name(index)
      names = info.dig('name').join(' | ').sub(picked_name, "*#{picked_name}")

      "#{names}\n#{pick_description(index)}"
    end

    def pick_description index
      info.dig('desc', index) || pick_description(index - 1) if index >= 0
    end

    def number
      "#{sequence}#{track_label}"
    end

    def track_label
      (track + 'A'.ord).chr
    end

    def == rhs
      id == rhs.id
    end

    def duped? rhs
      rhs && rarity == Rare && id == rhs.id
    end

    def new_with **args
      self.class.new(to_h.merge(args))
    end

    def rarity_label
      super ||
        case score
        when nil, 0...6500
          :rare
        when 6500...7000
          :supa_fest
        when 7000...9100
          :supa
        when 9100...9500
          :uber_fest
        when 9500...9970
          :uber
        else
          :legend
        end
    end
  end
end
