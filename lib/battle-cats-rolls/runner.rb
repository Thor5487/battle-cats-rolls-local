# frozen_string_literal: true

require_relative 'aws_auth'

module BattleCatsRolls
  class Runner < Struct.new(:lang, :version, :event_url, :apk_url)
    def self.en
      @en ||= [
        __method__,
        '9.8.0',
        AwsAuth.event_url('en'),
        # 'https://www.apkmonk.com/app/jp.co.ponos.battlecatsen/'
        'https://apkplz.net/app/jp.co.ponos.battlecatsen'
      ]
    end

    def self.tw
      @tw ||= [
        __method__,
        '9.8.0',
        AwsAuth.event_url('tw'),
        'https://www.apkmonk.com/app/jp.co.ponos.battlecatstw/'
        # 'https://apkplz.net/app/jp.co.ponos.battlecatstw'
      ]
    end

    def self.jp
      @jp ||= [
        __method__,
        '9.9.0',
        AwsAuth.event_url('jp'),
        # 'https://www.apkmonk.com/app/jp.co.ponos.battlecats/'
        'https://apkplz.net/app/jp.co.ponos.battlecats'
      ]
    end

    def self.kr
      @kr ||= [
        __method__,
        '9.8.0',
        AwsAuth.event_url('kr'),
        # 'https://www.apkmonk.com/app/jp.co.ponos.battlecatskr/'
        'https://apkplz.net/app/jp.co.ponos.battlecatskr'
      ]
    end

    def self.locale lang
      public_send(lang || :en)
    end

    def self.build lang=nil
      runner = new(*locale(lang))

      runner.write_events
      runner.write_data
    end

    def self.extract lang=nil, dir=nil
      new(*locale(lang)).extract(dir)
    end

    def self.list lang=nil, dir=nil
      new(*locale(lang)).list(dir)
    end

    def self.favicon lang=nil
      new(*locale(lang)).favicon
    end

    def extract dir=nil
      require_relative 'pack_reader'
      require 'fileutils'

      each_list(dir) do |file|
        reader = PackReader.new(file)

        dir = "#{extract_path}/#{reader.name}.pack"
        FileUtils.mkdir_p(dir)

        puts "Extracting #{reader.pack_path}"

        reader.each do |filename, data|
          File.binwrite("#{dir}/#{filename}", data.call)
        end
      end
    end

    def list dir=nil
      require_relative 'unpacker'

      unpacker = Unpacker.for_list

      each_list(dir) do |file|
        puts "#{file}:"
        puts unpacker.decrypt(File.binread(file))
        puts "---"
      end
    end

    def favicon
      require_relative 'pack_reader'
      require 'fileutils'

      reader = PackReader.new("#{app_data_path}/ImageLocal.list")

      dir = "#{extract_path}/#{reader.name}.pack"
      asset = "lib/battle-cats-rolls/asset/image"
      FileUtils.mkdir_p(dir)
      FileUtils.mkdir_p(asset)

      puts "Extracting #{reader.pack_path}"

      mapicon, data = reader.find do |filename, _|
        filename == 'mapicon.png'
      end

      path = "#{dir}/#{mapicon}"

      File.binwrite(path, data.call)

      puts "Cropping #{path}"

      # Install ImageMagick for this
      system('convert', '-crop', '60x60+60+0', path, "#{asset}/treasure.png")

      cats = "#{asset}/cats.png"
      system('convert', '-crop', '60x60+120+0', path, cats)
      system('convert', '-resize', '50x50', cats, cats)
      system('convert', '-border', '5', '-bordercolor', 'none', cats, cats)

      help = "#{asset}/help.png"
      system('convert', '-crop', '60x60+180+0', path, help)
      system('convert', '-resize', '46x46', help, help)
      system('convert', '-border', '7', '-bordercolor', 'none', help, help)

      logs = "#{asset}/logs.png"
      system('convert', '-crop', '60x60+240+0', path, logs)
      system('convert', '-resize', '44x44', logs, logs)
      system('convert', '-border', '8', '-bordercolor', 'none', logs, logs)

      seek = "#{asset}/seek.png"
      system('convert', '-crop', '60x60+300+0', path, seek)
      system('convert', '-resize', '46x46', seek, seek)
      system('convert', '-border', '7', '-bordercolor', 'none', seek, seek)
    end

    def write_events
      current = download_current_event_data

      last_date = current.gacha.
        delete_if { |_, data| data['platinum'] }.
        sort_by { |key, data| data['end_on'] }.
        dig(-1, -1, 'end_on').
        strftime('%Y%m%d')

      require 'fileutils'
      FileUtils.mkdir_p(event_path)

      File.write("#{event_path}/#{last_date}.tsv", current.tsv)
    end

    def download_current_event_data
      puts "Downloading event data..."

      require_relative 'tsv_reader'

      TsvReader.download(event_url)
    end

    def write_data
      require_relative 'events_reader'
      require_relative 'crystal_ball'

      events = EventsReader.read(event_path)
      ball = CrystalBall.from_pack_and_events(cats_pack, events)

      puts "Writing data..."

      ball.dump('build', lang)
    end

    def cats_pack
      require_relative 'cats_builder'

      CatsBuilder.new(provider)
    end

    def provider
      if File.exist?(extract_path)
        load_extract
      elsif File.exist?(app_data_path) && Dir["#{app_data_path}/*"].any?
        load_pack
      else
        download_apk unless File.exist?(apk_path)
        write_pack
        load_pack
      end
    end

    def download_apk
      puts "Downloading APK..."

      require 'fileutils'
      FileUtils.mkdir_p(app_data_path)

      case apk_url
      when %r{apkmonk\.com/app}
        wget(monk_donwload_link(apk_url), apk_path)
      when %r{apkplz\.net/app}
        wget(plz_download_link(*plz_download_link(apk_url)).first, apk_path)
      else
        wget(apk_url, apk_path)
      end
    end

    def monk_donwload_link url
      require 'json'

      uri = URI.parse(url)

      path, = css_download_link(url) do |title|
        "a[title~='#{title.downcase}']"
      end

      *, pkg, key = path.split('/')
      json_uri =
        "#{uri.scheme}://#{uri.host}/down_file/?pkg=#{pkg}&key=#{key}"

      json, = net_get(json_uri)

      JSON.parse(json)['url']
    end

    def plz_download_link url, laravel_session=nil
      css_download_link(url, laravel_session) do |title|
        "a[title~='#{title}']"
      end
    end

    def css_download_link url, laravel_session=nil
      require 'nokogiri'

      doc, new_laravel_session = net_get(url, laravel_session)

      title = "#{version} APK"
      link = Nokogiri::HTML.parse(doc).css(yield(title)).first&.attr('href')

      if link
        [link, new_laravel_session]
      else
        raise("Cannot find #{title} link")
      end
    end

    def net_get url, laravel_session=nil
      require 'net/http'

      uri = URI.parse(url)
      get = Net::HTTP::Get.new(uri)
      get['User-Agent'] = 'Mozilla/5.0'
      get['Cookie'] = "laravel_session=#{laravel_session}" if laravel_session

      response =
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(get)
        end

      new_laravel_session = response['set-cookie'][/laravel_session=(.+);/, 1]

      [response.body, new_laravel_session]
    end

    def wget url, path
      system(
        'wget',
        '--user-agent=Mozilla/5.0',
        '-O', path,
        url)
    end

    def open_uri uri
      URI.open(URI.parse(uri), 'User-Agent' => 'Mozilla/5.0')
    end

    def write_pack
      paths =
        %w[DataLocal resLocal ImageLocal].product(
          ['.list', '.pack']).map(&:join).map do |name|
          "assets/#{name}"
        end

      system('unzip', apk_path, *paths, '-d', app_data_path)

      require 'fileutils'
      assets = Dir["#{app_data_path}/assets/*"]
      FileUtils.mv(assets, app_data_path, verbose: true)
      FileUtils.rmdir("#{app_data_path}/assets", verbose: true)
    end

    def each_list dir=nil
      root = dir || app_data_path

      Dir["#{root}/**/*.list"].each do |file|
        yield(file)
      end
    end

    def load_extract
      puts "Loading from extract..."

      require_relative 'extract_provider'

      ExtractProvider.new(extract_path)
    end

    def load_pack
      puts "Loading from pack..."

      require_relative 'pack_provider'

      PackProvider.new(lang, app_data_path)
    end

    def event_path
      @event_path ||= "data/#{lang}/events"
    end

    def extract_path
      @extract_path ||= "extract/#{lang}/#{version}"
    end

    def app_data_path
      @data_path ||= "data/#{lang}/#{version}/app"
    end

    def apk_path
      @apk_path ||= "data/#{lang}/#{version}/bc-#{lang}.apk"
    end
  end
end
