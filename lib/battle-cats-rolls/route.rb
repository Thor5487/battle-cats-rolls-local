# frozen_string_literal: true

require_relative 'crystal_ball'
require_relative 'gacha_pool'
require_relative 'gacha'
require_relative 'owned'
require_relative 'aws_auth'
require_relative 'find_cat'
require_relative 'cat'

require 'cgi'
require 'date'
require 'forwardable'

module BattleCatsRolls
  class Route < Struct.new(:request)
    def self.root
      @root ||= "#{__dir__}/../.."
    end

    def self.ball_en
      @ball_en ||= CrystalBall.load("#{root}/build", 'en')
    end

    def self.ball_tw
      @ball_tw ||= CrystalBall.load("#{root}/build", 'tw')
    end

    def self.ball_jp
      @ball_jp ||= CrystalBall.load("#{root}/build", 'jp')
    end

    def self.ball_kr
      @ball_kr ||= CrystalBall.load("#{root}/build", 'kr')
    end

    extend Forwardable

    def_delegator :request, :path_info

    def gacha
      @gacha ||= Gacha.new(pool, seed, version)
    end

    def ball
      @ball ||= Route.public_send("ball_#{lang}")
    end

    def cats
      ball.cats
    end

    def seek_source
      @seek_source ||=
        [version, gacha.rare, gacha.supa, gacha.uber, gacha.legend,
         gacha.rare_cats.size, gacha.supa_cats.size,
         gacha.uber_cats.size, gacha.legend_cats.size,
         *request.POST['rolls']].join(' ').squeeze(' ')
    end

    def seek_result key
      "/seek/result/#{key}?" \
        "event=#{event}&lang=#{lang}&version=#{version}&name=#{name}"
    end

    def show_tracks?
      event && seed.nonzero? && gacha.pool.exist?
    end

    def prepare_tracks
      gacha.pool.add_future_ubers(ubers) if ubers > 0

      if last.nonzero?
        gacha.last_cat = Cat.new(id: last)
        gacha.last_both = [gacha.last_cat, nil]
      end

      # Human counts from 1
      cats = 1.upto(count).map do |sequence|
        gacha.roll_both!(sequence)
      end

      if version == '8.6'
        gacha.finish_rerolled_links(cats)
      end

      if guaranteed_rolls > 0
        gacha.finish_guaranteed(cats, guaranteed_rolls)
      end

      if pick = request.params['pick']
        gacha.finish_picking(cats, pick, guaranteed_rolls)
      end

      found_cats =
        FindCat.search(gacha, find,
          cats: cats, guaranteed: !no_guaranteed, max: FindCat::Max)

      [cats, found_cats]
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

    def uri path: "//#{web_host}/", query: {}
      query = cleanup_query(default_query(query))

      if query.empty?
        path
      else
        "#{path}?#{query_string(query)}"
      end
    end

    def seek_host
      ENV['SEEK_HOST'] || request.host_with_port
    end

    def web_host
      ENV['WEB_HOST'] || request.host_with_port
    end

    def tsv_expires_in
      600
    end

    def lang
      @lang ||=
        case value = request.params['lang']
        when 'tw', 'jp', 'kr'
          value
        else
          'en'
        end
    end

    def version
      @version ||=
        case value = request.params['version']
        when '8.6', '8.5', '8.4'
          value
        else
          default_version
        end
    end

    def default_version
      case lang
      when 'jp'
        '8.6'
      else
        '8.6'
      end
    end

    def name
      @name ||=
        case value = request.params['name'].to_i
        when 1, 2
          value
        else
          0
        end
    end

    # This is the seed from the seed input field
    def seed
      @seed ||= request.params['seed'].to_i
    end

    def event
      @event ||= request.params['event'] || current_event
    end

    def upcoming_events
      @upcoming_events ||= grouped_events[true] || []
    end

    def past_events
      @past_events ||= grouped_events[false] || []
    end

    def custom
      @custom ||=
        (request.params['custom'] ||
          ball.gacha.each_key.reverse_each.first).to_i
    end

    def predefined_rates
      @predefined_rates ||= {
        regular: {name: 'Regular', rate: [6970, 2500, 500]},
        no_legend: {name: 'Regular without legend', rate: [7000, 2500, 500]},
        festival: {name: 'Uberfest / Epicfest', rate: [6500, 2600, 900]},
        superfest: {name: 'Superfest', rate: [6500, 2500, 1000]},
        platinum: {name: 'Platinum', rate: [0, 0, 10000]},
        '': {name: 'Customize...'}
      }
    end

    def rate
      @rate ||= request.params['rate'].to_s.to_sym
    end

    def c_rare
      @c_rare ||= get_rate('c_rare', 0)
    end

    def c_supa
      @c_supa ||= get_rate('c_supa', 1)
    end

    def c_uber
      @c_uber ||= get_rate('c_uber', 2)
    end

    def count
      @count ||=
        [1,
         [(request.params['count'] || 100).to_i, FindCat::Max].min
        ].max
    end

    def find
      @find ||= request.params['find'].to_i
    end

    def last
      @last ||= request.params['last'].to_i
    end

    def no_guaranteed
      return @no_guaranteed if instance_variable_defined?(:@no_guaranteed)

      @no_guaranteed =
        !request.params['no_guaranteed'].to_s.strip.empty? || nil
    end

    def force_guaranteed
      @force_guaranteed ||= request.params['force_guaranteed'].to_i
    end

    def guaranteed_rolls
      @guaranteed_rolls ||=
        if force_guaranteed.zero?
          gacha.pool.guaranteed_rolls
        else
          force_guaranteed
        end
    end

    def ubers
      @ubers ||= request.params['ubers'].to_i
    end

    def details
      return @details if instance_variable_defined?(:@details)

      @details = !request.params['details'].to_s.strip.empty? || nil
    end

    def o
      @o ||=
        if owned.any?
          Owned.encode(owned)
        else
          ''
        end
    end

    def owned
      @owned ||=
        if ticked.any?
          ticked
        elsif (result = Owned.decode(request.params['o'].to_s)).any?
          result
        else
          Owned.decode_old(request.params['owned'].to_s)
        end.sort.uniq
    end

    def ticked
      @ticked ||= Array(request.params['t']).map(&:to_i).sort.uniq
    end

    def uri_to_roll cat
      uri(query: {seed: cat.slot_fruit.seed, last: cat.id})
    end

    def event_url *args, **options
      AwsAuth.event_url(lang, *args, base_uri: event_base_uri, **options)
    end

    private

    def pool
      @pool ||=
        case event
        when 'custom'
          event_data = {
            'id' => custom,
            'rare' => c_rare,
            'supa' => c_supa,
            'uber' => c_uber
          }

          GachaPool.new(ball, event_data: event_data)
        else
          GachaPool.new(ball, event_name: event)
        end
    end

    def current_event
      @current_event ||=
        upcoming_events.find{ |_, info| info['platinum'].nil? }&.first
    end

    def grouped_events
      @grouped_events ||= begin
        today = Date.today

        all_events.group_by do |_, value|
          if value['platinum']
            current_platinum['id'] == value['id'] ||
              today <= value['start_on'] # Include upcoming platinum
          else
            today <= value['end_on']
          end
        end
      end
    end

    def current_platinum
      @current_platinum ||= begin
        past = Date.new
        today = Date.today

        all_events.max_by do |_, value|
          # Ignore upcoming platinum
          if value['platinum'] && value['start_on'] <= today
            value['start_on']
          else
            past
          end
        end.last
      end
    end

    def all_events
      @all_events ||= ball.events
    end

    def get_rate name, index
      int = request.params[name] || predefined_rates.dig(rate, :rate, index)

      [int.to_i.abs, 10000].min
    end

    def event_base_uri
      "#{request.scheme}://#{seek_host}/seek"
    end

    def query_string query
      query.map do |key, value|
        "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
      end.join('&')
    end

    def default_query query={}
      %i[
        seed last event custom rate c_rare c_supa c_uber lang version
        name count find no_guaranteed force_guaranteed ubers details
        o
      ].inject({}) do |result, key|
        result[key] = query[key] || __send__(key)
        result
      end
    end

    def cleanup_query query
      query.compact.select do |key, value|
        if (key == :seed && value == 0) ||
           (key == :lang && value == 'en') ||
           (key == :version && value == default_version) ||
           (key == :name && value == 0) ||
           (key == :count && value == 100) ||
           (key == :find && value == 0) ||
           (key == :last && value == 0) ||
           (key == :no_guaranteed && value == 0) ||
           (key == :force_guaranteed && value == 0) ||
           (key == :ubers && value == 0) ||
           (key == :o && value == '') ||
           (query[:event] != 'custom' &&
              (key == :custom || key == :rate ||
               key == :c_rare || key == :c_supa || key == :c_uber)) ||
           (query[:event] == 'custom' &&
              (
                (key == :rate && value == :'') ||
                (query[:rate] != :'' &&
                  (key == :c_rare || key == :c_supa || key == :c_uber))
              ))
          false
        else
          true
        end
      end
    end
  end
end
