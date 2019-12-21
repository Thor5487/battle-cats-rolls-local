# frozen_string_literal: true

require_relative 'cat'
require_relative 'fruit'
require_relative 'gacha_pool'

require 'forwardable'

module BattleCatsRolls
  class Gacha < Struct.new(:pool, :seed, :version, :last_both)
    extend Forwardable

    def_delegators :pool, *%w[rare supa uber legend]

    def initialize crystal_ball, event_name, seed, version
      super(GachaPool.new(crystal_ball, event_name), seed, version, [])

      advance_seed!
    end

    %w[Rare Supa Uber Legend].each do |rarity|
      define_method("#{rarity.downcase}_cats") do
        name = "@#{__method__}"

        instance_variable_get(name) ||
          instance_variable_set(name,
            pick_cats(Cat.const_get(rarity)))
      end
    end

    def roll_both! sequence=nil
      a_fruit = roll_fruit!
      b_fruit = roll_fruit
      a_cat = roll_cat!(a_fruit)
      b_cat = roll_cat(b_fruit)
      a_cat.track = 0
      b_cat.track = 1
      a_cat.sequence = b_cat.sequence = sequence

      fill_cat_links(a_cat, last_both.first)
      fill_cat_links(b_cat, last_both.last)

      self.last_both = [a_cat, b_cat]
    end

    def roll!
      roll_cat!(roll_fruit!)
    end

    # Existing dupes can cause more dupes, see this for bouncing around:
    # https://bc.godfat.org/?seed=2263031574&event=2019-11-27_377
    def finish_rerolled_links cats
      each_cat(cats) do |rolled_cat, index, track|
        next unless rerolled = rolled_cat.rerolled

        next_index = index + rerolled.steps + track
        next_track = ((track + rerolled.steps - 1) ^ 1) & 1
        next_cat = cats.dig(next_index, next_track)

        fill_cat_links(next_cat, rerolled) if next_cat
      end
    end

    def finish_guaranteed cats, guaranteed_rolls=pool.guaranteed_rolls
      each_cat(cats) do |rolled_cat|
        fill_guaranteed(cats, guaranteed_rolls, rolled_cat)

        if rolled_cat.rerolled
          fill_guaranteed(cats, guaranteed_rolls, rolled_cat.rerolled)
        end
      end
    end

    # This can see A and B are passing each other:
    # https://bc.godfat.org/?seed=2390649859&event=2019-06-06_318
    def finish_picking cats, pick, guaranteed_rolls=pool.guaranteed_rolls
      index = pick.to_i - 1
      track = (pick[/\A\d+(\w)/, 1] || 'A').ord - 'A'.ord
      located = cats.dig(index, track)
      picked =
        if pick.include?('R')
          located.rerolled
        else
          located
        end

      return unless picked # Users can give arbitrary input
      return unless picked.guaranteed if pick.include?('G')

      if pick.include?('X')
        if pick.include?('G')
          fill_picking_guaranteed(cats, picked, /\A#{picked.number}/,
            guaranteed_rolls)
        else
          fill_picking_single(cats, picked, /\A#{picked.number}/)
        end
      elsif pick.include?('G')
        fill_picking_guaranteed(cats, picked, "#{picked.number}G",
          guaranteed_rolls)
      else
        fill_picking_single(cats, picked, picked.number)
      end
    end

    private

    def pick_cats rarity
      pool.dig_slot(rarity).map do |id|
        Cat.new(id: id, info: pool.dig_cat(rarity, id), rarity: rarity)
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

    def new_cat rarity, slot_fruit, **args
      slots = pool.dig_slot(rarity)
      slot = slot_fruit.value % slots.size
      id = slots[slot]

      Cat.new(
        id: id, info: pool.dig_cat(rarity, id),
        rarity: rarity,
        slot_fruit: slot_fruit, slot: slot,
        **args)
    end

    def reroll_cat cat
      rarity = cat.rarity
      rerolling_slots = pool.dig_slot(rarity).dup
      next_seed = cat.slot_fruit.value
      slot = cat.slot
      id = nil

      # This can run up to the number of duplicated cats
      # 2: https://bc.godfat.org/?seed=3419147157&event=2019-07-18_391
      # 4: https://bc.godfat.org/?seed=2116007321&event=2019-07-21_391&pick=1AG
      steps = (1..rerolling_slots.count(cat.id)).find do
        next_seed = advance_seed(next_seed)
        rerolling_slots.delete_at(slot)

        slot = next_seed % rerolling_slots.size
        id = rerolling_slots[slot]

        id != cat.id
      end

      Cat.new(
        id: id, info: pool.dig_cat(rarity, id),
        rarity: rarity, score: cat.score,
        slot_fruit: roll_fruit(next_seed), slot: slot,
        sequence: cat.sequence, track: cat.track, steps: steps,
        extra_label: "#{cat.extra_label}R")
    end

    def fill_cat_links cat, last_cat
      if version == '8.6' && cat.duped?(last_cat)
        last_cat.next = cat.rerolled = reroll_cat(cat)
      elsif last_cat
        last_cat.next = cat
      end
    end

    def each_cat cats
      cats.each.with_index do |row, index|
        row.each.with_index do |rolled_cat, track|
          yield(rolled_cat, index, track)
        end
      end
    end

    def fill_guaranteed cats, guaranteed_rolls, rolled_cat
      return unless last = follow_cat(rolled_cat, guaranteed_rolls - 1)

      next_index = last.sequence - (last.track ^ 1)
      next_track = last.track ^ 1
      next_cat = cats.dig(next_index, next_track)

      if next_cat
        guaranteed_slot_fruit =
          cats.dig(last.sequence - 1, last.track, :rarity_fruit)

        rolled_cat.guaranteed =
          new_cat(
            Cat::Uber, guaranteed_slot_fruit,
            sequence: rolled_cat.sequence,
            track: rolled_cat.track,
            next: next_cat,
            extra_label: "#{rolled_cat.extra_label}G")
      end
    end

    # We should find a way to optimize this so that
    # we don't have to follow tightly in a loop!
    # How do we reuse the calculation?
    def follow_cat cat, steps
      steps.times.inject(cat) do |result|
        result.next || break
      end
    end

    def fill_picking_single cats, picked, number
      detected = fill_picking_backtrack(cats, number)

      # Might not find the way back
      # https://bc.godfat.org/?seed=3419147157&event=2019-07-21_391&pick=44AX#N44A
      the_cat = detected || picked
      the_cat.picked_label = :picked
      the_cat.next&.picked_label = :next_position
    end

    def fill_picking_guaranteed cats, picked, number, guaranteed_rolls
      detected = fill_picking_backtrack(cats, number, :guaranteed)

      # Might not find the way back
      # https://bc.godfat.org/?seed=3419147157&event=2019-07-21_391&pick=44AGX#N44A
      the_cat = detected || picked
      guaranteed = the_cat.guaranteed
      guaranteed.picked_label = :picked_cumulatively
      guaranteed.next&.picked_label = :next_position

      (guaranteed_rolls - 1).times.inject(the_cat) do |rolled|
        rolled.picked_label = :picked_cumulatively
        rolled.next || break
      end
    end

    def fill_picking_backtrack cats, number, which_cat=:itself
      [
        fill_picking_backtrack_from(cats.dig(0, 0), number, which_cat),
        fill_picking_backtrack_from(cats.dig(0, 1), number, which_cat)
      ].find(&:itself)
    end

    def fill_picking_backtrack_from cat, number, which_cat=:itself
      path = []

      begin
        checking_cat = cat.public_send(which_cat)

        if checking_cat.nil? # Guaranteed might not exist due to missing seeds
          break
        elsif number === checking_cat.number # String or Regexp matching
          path.each do |passed_cat|
            passed_cat.picked_label = :picked
          end

          break cat
        else
          path << cat
        end
      end while cat = cat.next
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
