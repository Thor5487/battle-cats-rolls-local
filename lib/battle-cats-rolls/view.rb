# frozen_string_literal: true

require_relative 'cat'
require_relative 'find_cat'
require_relative 'aws_auth'

require 'cgi'
require 'erb'
require 'tilt'

require 'forwardable'

module BattleCatsRolls
  class View < Struct.new(:controller, :arg)
    extend Forwardable

    def_delegators :controller, *%w[request gacha]

    def render name
      erb(:layout){ erb(name) }
    end

    private

    def each_ball_cat
      arg[:cats].reverse_each do |rarity, data|
        yield(rarity, data.map{ |id, info| Cat.new(id: id, info: info) })
      end
    end

    def each_ab_cat
      arg[:cats].inject(nil) do |prev_b, ab|
        yield(prev_b, ab)

        ab.last
      end
    end

    def color_label cat, type, rerolled
      return unless cat

      if type == :cat || !(rerolled || cat.rerolled)
        picked = cat.picked_label
        cursor = :pick
      else
        cursor = :navigate
      end

      "#{cursor} #{color_rarity(cat)} #{picked}".chomp(' ')
    end

    def color_rarity cat
      case rarity_label = cat.rarity_label
      when :legend
        :legend
      else
        case cat.id
        when controller.find
          :found
        when *controller.owned_decoded
          :owned
        when *FindCat.exclusives
          :exclusive
        else
          rarity_label
        end
      end
    end

    def color_guaranteed cat
      case cat.guaranteed.id
      when controller.find
        :found
      when *FindCat.exclusives
        :exclusive
      when Integer
        :rare
      end
    end

    def number_td cat, other_cat
      rowspan = 2 + [cat.rerolled, other_cat&.rerolled].compact.size

      <<~HTML
        <td rowspan="#{rowspan}" id="N#{cat.number}">#{cat.number}</td>
      HTML
    end

    def score_tds cat, other_cat
      rowspan =
        if other_cat&.rerolled
          2
        else
          1
        end

      content =
        if show_details
          "#{cat.score}, #{cat.slot}"
        else
          "\u00A0"
        end

      single = td(cat, :score, rowspan: rowspan, content: content)
      guaranteed = td(cat.guaranteed, :score, rowspan: rowspan,
        rerolled: cat.rerolled&.guaranteed)

      "#{single}\n#{guaranteed}"
    end

    def cat_tds cat, type=:roll
      single = td_to_cat(cat, type)
      guaranteed = td_to_cat(cat.guaranteed, :next)

      "#{single}\n#{guaranteed}"
    end

    def td_to_cat cat, link_type
      td(cat, :cat, content: cat && __send__("link_to_#{link_type}", cat))
    end

    def td cat, type, rowspan: 1, content: nil, rerolled: nil
      <<~HTML
        <td
          rowspan="#{rowspan}"
          class="#{type} #{color_label(cat, type, rerolled)}"
          #{onclick_pick(cat, type)}>
          #{content}
        </td>
      HTML
    end

    def link_to_roll cat
      name = h cat.pick_name(controller.name)
      title = h cat.pick_title(controller.name)

      if cat.slot_fruit
        %Q{<a href="#{h uri_to_roll(cat)}" title="#{title}">#{name}</a>}
      else
        %Q{<span title="#{title}">#{name}</span>}
      end +
        if cat.id > 0
          %Q{<a href="#{h uri_to_cat_db(cat)}">🐾</a>}
        else
          ''
        end
    end

    def link_to_next cat
      cat_link = link_to_roll(cat)
      next_cat = cat.next

      case next_cat&.track
      when 0
        "&lt;- #{next_cat.number} #{cat_link}"
      when 1
        "#{cat_link} -&gt; #{next_cat.number}"
      when nil
        "&lt;?&gt; #{cat_link}"
      else
        raise "Unknown track: #{next_cat.track.inspect}"
      end
    end

    def pick_option cats
      cats.map.with_index do |cat, slot|
        <<~HTML
          <option value="#{cat.rarity} #{slot}">#{slot} #{cat_name(cat)}</option>
        HTML
      end.join
    end

    def selected_lang lang_name
      'selected="selected"' if controller.lang == lang_name
    end

    def selected_version version_name
      'selected="selected"' if controller.version == version_name
    end

    def selected_name name_name
      'selected="selected"' if controller.name == name_name
    end

    def selected_current_event event_name
      'selected="selected"' if controller.event == event_name
    end

    def selected_find cat
      'selected="selected"' if controller.find == cat.id
    end

    def selected_last cat
      'selected="selected"' if controller.last == cat.id
    end

    def checked_no_guaranteed
      'checked="checked"' if controller.no_guaranteed
    end

    def selected_force_guaranteed n
      'selected="selected"' if controller.force_guaranteed == n
    end

    def selected_ubers n
      'selected="selected"' if controller.ubers == n
    end

    def checked_details
      'checked="checked"' if controller.details
    end

    def checked_cat cat
      ticked = controller.ticked

      if ticked.empty?
        'checked="checked"' if controller.owned_decoded.include?(cat.id)
      elsif ticked.include?(cat.id)
        'checked="checked"'
      end
    end

    def show_details
      arg&.dig(:details) && controller.details
    end

    def hidden_inputs *input_names
      input_names.map do |name|
        <<~HTML
          <input type="hidden" name="#{name}" value="#{controller.public_send(name)}">
        HTML
      end.join("\n")
    end

    def show_event info
      h "#{info['start_on']} ~ #{info['end_on']}: #{info['name']}"
    end

    def show_gacha_slots cats
      cats.map.with_index do |cat, i|
        "#{i} #{cat_name(cat)}"
      end.join(', ')
    end

    def cat_name cat
      h cat.pick_name(controller.name)
    end

    def event_url *args, **options
      AwsAuth.event_url(*args, base_uri: event_base_uri, **options)
    end

    def h str
      CGI.escape_html(str)
    end

    def u str
      CGI.escape(str)
    end

    def made10rolls? seeds
      gacha = Gacha.new(
        controller.ball, controller.event, seeds.first, controller.version)
      gacha.send(:advance_seed!) # Account offset
      9.times.inject(nil){ |last| gacha.roll! } # Only 9 rolls left

      if gacha.seed == seeds.last
        gacha.send(:advance_seed!) # Account for guaranteed roll
        gacha.seed
      end
    end

    def header n, name
      id = name.to_s.downcase.gsub(/\W+/, '-')

      <<~HTML
        <a href="##{id}">⚓</a> <h#{n} id="#{id}">#{name}</h#{n}>
      HTML
    end

    def seed_tds fruit, cat
      return unless show_details

      rowspan =
        if cat&.rerolled
          2
        else
          1
        end

      value =
        if fruit.seed == fruit.value
          '-'
        else
          fruit.value
        end

      <<~HTML
        <td rowspan="#{rowspan}">#{fruit.seed}</td>
        <td rowspan="#{rowspan}">#{value}</td>
      HTML
    end

    def onclick_pick cat, type
      return unless cat && controller.path_info == '/'

      number =
        case type
        when :cat
          cat.number
        else
          "#{cat.number}X"
        end

      %Q{onclick="pick('#{number}')"}
    end

    def uri_to_roll cat
      uri(query: {seed: cat.slot_fruit.seed, last: cat.id})
    end

    def uri_to_cat_db cat
      "https://battlecats-db.com/unit/#{sprintf('%03d', cat.id)}.html"
    end

    def uri_to_own_all_cats
      cats_uri(query: {owned:
        Owned.encode(arg[:cats].values.flat_map{ |data| data.map(&:first) })})
    end

    def uri_to_drop_all_cats
      cats_uri(query: {owned: ''})
    end

    def uri path: "//#{web_host}/", query: {}
      # keep query hash order
      query = cleanup_query(query.merge(default_query).merge(query))

      if query.empty?
        path
      else
        "#{path}?#{query_string(query)}"
      end
    end

    def default_query
      {
        seed: controller.seed,
        last: controller.last,
        event: controller.event,
        lang: controller.lang,
        version: controller.version,
        name: controller.name,
        count: controller.count,
        find: controller.find,
        no_guaranteed: controller.no_guaranteed,
        force_guaranteed: controller.force_guaranteed,
        ubers: controller.ubers,
        details: controller.details,
        owned: controller.owned
      }
    end

    def cleanup_query query
      query.compact.select do |key, value|
        if (key == :seed && value == 0) ||
           (key == :lang && value == 'en') ||
           (key == :version && value == controller.default_version) ||
           (key == :name && value == 0) ||
           (key == :count && value == 100) ||
           (key == :find && value == 0) ||
           (key == :last && value == 0) ||
           (key == :no_guaranteed && value == 0) ||
           (key == :force_guaranteed && value == 0) ||
           (key == :ubers && value == 0) ||
           (key == :owned && value == '')
          false
        else
          true
        end
      end
    end

    def query_string query
      query.map do |key, value|
        "#{u key.to_s}=#{u value.to_s}"
      end.join('&')
    end

    def seek_host
      ENV['SEEK_HOST'] || request.host_with_port
    end

    def web_host
      ENV['WEB_HOST'] || request.host_with_port
    end

    def event_base_uri
      "#{request.scheme}://#{seek_host}/seek"
    end

    def cats_uri **args
      uri(path: "//#{web_host}/cats", **args)
    end

    def help_uri
      uri(path: "//#{web_host}/help")
    end

    def logs_uri
      uri(path: "//#{web_host}/logs")
    end

    def seek_uri
      uri(path: "//#{seek_host}/seek")
    end

    def erb name, nested_arg=nil, &block
      context =
        if nested_arg
          self.class.new(controller, arg&.merge(nested_arg) || nested_arg)
        else
          self
        end

      self.class.template(name).render(context, &block)
    end

    def self.template name
      (@template ||= {})[name.to_s] ||=
        Tilt.new("#{__dir__}/view/#{name}.erb")
    end

    def self.warmup
      prefix = Regexp.escape("#{__dir__}/view/")

      Dir.glob("#{__dir__}/view/**/*") do |name|
        next if File.directory?(name)

        template(name[/\A#{prefix}(.+)\.erb\z/m, 1])
      end
    end
  end
end
