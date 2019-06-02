# frozen_string_literal: true

require_relative 'cat'
require_relative 'fruit'
require_relative 'gacha_pool'

require 'forwardable'

module BattleCatsRolls
  class Gacha < Struct.new(:pool, :seed, :version, :last_both, :last_last)
    Rare   = 2
    Supa   = 3
    Uber   = 4
    Legend = 5

    extend Forwardable

    def_delegators :pool, *%w[rare supa uber legend]

    def initialize crystal_ball, event_name, seed, version
      super(GachaPool.new(crystal_ball, event_name), seed, version)
    end

    %w[Rare Supa Uber Legend].each do |rarity|
      define_method("#{rarity.downcase}_cats") do
        name = "@#{__method__}"

        instance_variable_get(name) ||
          instance_variable_set(name,
            pick_cats(self.class.const_get(rarity)))
      end
    end

    def current_seed_mode!
      advance_seed!
    end

    def roll_both_with_sequence! sequence
      roll_both!.each do |cat|
        cat.sequence = sequence
      end
    end

    def roll_both!
      a_fruit = roll_fruit!
      b_fruit = roll_fruit
      a_cat = roll_cat!(a_fruit, last_both&.first)
      b_cat = roll_cat(b_fruit, last_both&.last)
      a_cat.track = 'A'
      b_cat.track = 'B'

      fill_rerolled_slot_fruit(a_cat, b_cat)

      self.last_last = last_both
      self.last_both = [a_cat, b_cat]
    end

    def roll! last_cat
      roll_cat!(roll_fruit!, last_cat)
    end

    def fill_guaranteed cats, guaranteed_rolls=pool.guaranteed_rolls
      if guaranteed_rolls > 0
        cats.each.with_index do |ab, index|
          ab.each.with_index do |rolled_cat, a_or_b|
            guaranteed_slot_fruit =
              cats.dig(index + guaranteed_rolls - 1, a_or_b, :rarity_fruit)

            if guaranteed_slot_fruit
              rolled_cat.guaranteed = new_cat(Uber, guaranteed_slot_fruit)
              rolled_cat.guaranteed.sequence = rolled_cat.sequence
              rolled_cat.guaranteed.track = "#{rolled_cat.track}G"
            end
          end
        end
      end

      guaranteed_rolls
    end

    private

    def pick_cats rarity
      pool.dig_slot(rarity).map do |id|
        Cat.new(id, pool.dig_cat(rarity, id), rarity)
      end
    end

    def roll_fruit
      Fruit.new(seed, version)
    end

    def roll_fruit!
      roll_fruit.tap{ advance_seed! }
    end

    def roll_cat rarity_fruit, last_cat
      score = rarity_fruit.value % GachaPool::Base
      rarity = dig_rarity(score)
      slot_fruit = if block_given? then yield else roll_fruit end
      cat = new_cat(rarity, slot_fruit)

      cat.rarity_fruit = rarity_fruit
      cat.score = score

      determine_cat(cat, last_cat)
    end

    def roll_cat! rarity_fruit, last_cat
      roll_cat(rarity_fruit, last_cat){ roll_fruit! }
    end

    def determine_cat cat, last_cat
      return cat unless last_cat

      case version
      when '8.6'
        if cat.rarity == Rare && cat.id == last_cat.id
          cat.rerolled = reroll_cat
          cat
          # dupe detected!
          # we need to show all potential results coming from above or
          # the other track, because we don't know how people can get here:
          #
          # Original Cat | Dupe from above -> XB | Dupe from right -> YB
          # Original Cat | XA <- Dupe from above | YA <- Dupe from left
          #
          # also we better to remember which is the last cat people get,
          # so 1A can be more accurate
        else
          cat
        end
      when '8.5', '8.4'
        cat
      else
        raise "Unknown version: #{version}"
      end
    end

    def dig_rarity score
      rare_supa = rare + supa

      case score
      when 0...rare
        Rare
      when rare...rare_supa
        Supa
      when rare_supa...(rare_supa + uber)
        Uber
      else
        Legend
      end
    end

    def new_cat rarity, slot_fruit
      slot = slot_fruit.value % pool.dig_slot(rarity).size
      id = pool.dig_slot(rarity, slot)

      Cat.new(id, pool.dig_cat(rarity, id), rarity, slot_fruit, slot)
    end

    def reroll_cat
      Cat.new(0, 'name' => ['Rerolled rare'])
    end

    def fill_rerolled_slot_fruit *current
      if last_last
        last_last.each.with_index do |ll, index|
          if ll&.rerolled
            ll.rerolled.slot_fruit = current[index].rarity_fruit
          end
        end
      end
    end

    def advance_seed!
      self.seed = advance_seed
    end

    def advance_seed base_seed=seed
      base_seed = shift(:<<, 13, base_seed)
      base_seed = shift(:>>, 17, base_seed)
      base_seed = shift(:<<, 15, base_seed)
    end

    def shift direction, bits, base_seed=seed
      base_seed ^= base_seed.public_send(direction, bits) % 0x100000000
    end
  end
end
