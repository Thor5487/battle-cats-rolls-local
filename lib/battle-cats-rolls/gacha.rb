# frozen_string_literal: true

require_relative 'cat'
require_relative 'fruit'
require_relative 'gacha_pool'

require 'forwardable'

module BattleCatsRolls
  class Gacha < Struct.new(:pool, :seed, :version, :last_both, :last_last)
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
            pick_cats(Cat.const_get(rarity)))
      end
    end

    def current_seed_mode!
      advance_seed!
    end

    def roll_both! sequence=nil
      a_fruit = roll_fruit!
      b_fruit = roll_fruit
      a_cat = roll_cat!(a_fruit)
      b_cat = roll_cat(b_fruit)
      a_cat.track = 'A'
      b_cat.track = 'B'
      a_cat.sequence = b_cat.sequence = sequence

      fill_rerolled_cats(a_cat, b_cat) if version == '8.6'

      self.last_last = last_both
      self.last_both = [a_cat, b_cat]
    end

    def roll!
      roll_cat!(roll_fruit!)
    end

    def fill_guaranteed cats, guaranteed_rolls=pool.guaranteed_rolls
      if guaranteed_rolls > 0
        cats.each.with_index do |ab, index|
          ab.each.with_index do |rolled_cat, a_or_b|
            guaranteed_slot_fruit =
              cats.dig(index + guaranteed_rolls - 1, a_or_b, :rarity_fruit)

            if guaranteed_slot_fruit
              rolled_cat.guaranteed =
                new_cat(Cat::Uber, guaranteed_slot_fruit)
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

    def roll_fruit base_seed=seed
      Fruit.new(base_seed, version)
    end

    def roll_fruit!
      roll_fruit.tap{ advance_seed! }
    end

    def roll_cat rarity_fruit
      score = rarity_fruit.value % GachaPool::Base
      rarity = dig_rarity(score)
      slot_fruit = if block_given? then yield else roll_fruit end
      cat = new_cat(rarity, slot_fruit)

      cat.rarity_fruit = rarity_fruit
      cat.score = score

      cat
    end

    def roll_cat! rarity_fruit
      roll_cat(rarity_fruit){ roll_fruit! }
    end

    def dig_rarity score
      rare_supa = rare + supa

      case score
      when 0...rare
        Cat::Rare
      when rare...rare_supa
        Cat::Supa
      when rare_supa...(rare_supa + uber)
        Cat::Uber
      else
        Cat::Legend
      end
    end

    def new_cat rarity, slot_fruit
      slots = pool.dig_slot(rarity)
      slot = slot_fruit.value % slots.size
      id = slots[slot]

      Cat.new(id, pool.dig_cat(rarity, id), rarity, slot_fruit, slot)
    end

    def reroll_cat cat
      rarity = cat.rarity
      rerolling_slots = pool.dig_slot(rarity).dup
      next_seed = cat.slot_fruit.value
      slot = nil
      id = nil

      steps = (1..rerolling_slots.count(cat.id)).find do
        next_seed = advance_seed(next_seed)
        rerolling_slots.delete_at(rerolling_slots.index(cat.id))

        slot = next_seed % rerolling_slots.size
        id = rerolling_slots[slot]

        id != cat.id
      end

      rerolled =
        Cat.new(id, pool.dig_cat(rarity, id),
          rarity, roll_fruit(next_seed), slot)

      if steps.odd?
        rerolled.track = ('A'.ord + %w[B A].index(cat.track)).chr
        rerolled.sequence = cat.sequence.succ + steps / 2
        rerolled.sequence += 1 if cat.track == 'B'
      else
        rerolled.track = cat.track
        rerolled.sequence = cat.sequence.succ + steps / 2
      end

      rerolled
    end

    def fill_rerolled_cats a_cat, b_cat
      last_a, last_b = last_both
      last_last_a, last_last_b = last_last

      # Checking A with previous A
      if a_cat.duped?(last_a) ||
          # Checking A with previous B when swapping tracks
          a_cat.duped?(last_last_b&.rerolled)
        a_cat.rerolled = reroll_cat(a_cat)
      end

      # Checking B with previous B
      if last_b&.duped?(last_last_b) ||
          # Checking B with previous A when swapping tracks
          last_b&.duped?(last_last_a&.rerolled)
        last_b.rerolled = reroll_cat(last_b)
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
