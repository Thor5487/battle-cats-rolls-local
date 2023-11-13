# frozen_string_literal: true

require_relative 'root'
require_relative 'nyanko_auth'

module BattleCatsRolls
  class Runner < Struct.new(:lang, :version, :apk_id)
    VersionNotFound = Class.new(RuntimeError)

    def self.en
      @en ||= [
        'en',
        '12.7.0',
        'jp.co.ponos.battlecatsen'
      ]
    end

    def self.tw
      @tw ||= [
        'tw',
        '12.7.0',
        'jp.co.ponos.battlecatstw'
      ]
    end

    def self.jp
      @jp ||= [
        'jp',
        '13.0.0',
        'jp.co.ponos.battlecats'
      ]
    end

    def self.kr
      @kr ||= [
        'kr',
        '12.7.0',
        'jp.co.ponos.battlecatskr'
      ]
    end

    def self.locale lang
      public_send(lang || 'en')
    end

    def self.build lang=nil
      require 'socket'

      runner = new(*locale(lang))

      runner.write_events
      runner.write_data
      # runner.write_item_and_sale
    rescue Errno::EACCES, SocketError => e
      puts "! Ignore: #{e}"
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
        reader = PackReader.new(lang, file)

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

      reader = PackReader.new(lang, "#{app_data_path}/ImageLocal.list")

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
      write_tsv('gatya.tsv', 'events') do |reader|
        last_date(reader.gacha.reject { |_, data| data['platinum'] })
      end
    end

    def write_item_and_sale
      %w[item.tsv sale.tsv].each do |tsv|
        write_tsv(tsv) do |reader|
          last_date(reader.item_or_sale)
        end
      end
    end

    def write_tsv file, dir=File.basename(file, '.*')
      puts "Downloading #{file}..."

      require_relative 'tsv_reader'

      file_url = NyankoAuth.event_url(lang, file: file, jwt: jwt)
      reader = TsvReader.download(file_url)

      file_name = yield(reader)
      dir_path = data_path(dir)

      require 'fileutils'
      FileUtils.mkdir_p(dir_path)

      File.write("#{dir_path}/#{file_name}.tsv", reader.tsv)
    end

    def write_data
      require_relative 'events_reader'
      require_relative 'crystal_ball'

      if provider
        events = EventsReader.read(event_path)
        ball = CrystalBall.from_cats_builder_and_events(cats_builder, events)

        puts "Writing data..."

        ball.dump("#{Root}/build", lang)
      end
    end

    def cats_builder
      require_relative 'cats_builder'

      CatsBuilder.new(provider)
    end

    def provider
      @provider ||=
        if File.exist?(extract_path)
          load_extract
        elsif File.exist?(app_data_path) && Dir["#{app_data_path}/*"].any?
          load_pack
        else
          if File.exist?(apk_path) || download_apk
            write_pack && load_pack
          else
            puts "! Cannot find '#{version}' for #{lang}"
          end
        end
    end

    def download_apk
      %w[
        https://www.apkmonk.com/app/%{id}/
        https://apksos.com/app/%{id}
        https://d.apkpure.com/b/APK/%{id}
      ].find do |template|
        download_apk_from(sprintf(template, id: apk_id))
      end
    end

    def download_apk_from apk_url
      puts "Downloading APK from #{apk_url}"

      require 'fileutils'
      FileUtils.mkdir_p(app_data_path)

      case apk_url
      when %r{apkmonk\.com/app}
        wget(monk_donwload_link(apk_url), apk_path)
      when %r{apksos\.com/app}
        wget(sos_download_link(*sos_download_link(apk_url)).first, apk_path)
        extract_sos_bundle
      when %r{apkpure\.com/b/APK}
        wget("#{apk_url}?versionCode=#{version_id}", apk_path)
      else
        wget(apk_url, apk_path)
      end
    rescue VersionNotFound
      false
    else
      true
    end

    def monk_donwload_link url
      require 'json'

      uri = URI.parse(url)

      path, = css_download_link(url) do |title|
        "a[title*='#{title.downcase}']"
      end

      *, pkg, key = path.split('/')
      json_uri =
        "#{uri.scheme}://#{uri.host}/down_file/?pkg=#{pkg}&key=#{key}"

      json, = net_get(json_uri)

      JSON.parse(json)['url']
    end

    def sos_download_link url, laravel_session=nil
      css_download_link(url, laravel_session) do |title|
        "a[title*='#{title}']"
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
        raise(VersionNotFound.new("Cannot find #{title} link"))
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

      cookie = response['set-cookie']
      new_laravel_session = cookie[/laravel_session=(.+);/, 1] if cookie

      [response.body, new_laravel_session]
    end

    def wget_response url, _=nil
      require 'tempfile'

      response = Tempfile.open('wget_response') do |file|
        wget(url, file.path)
        file.rewind
        file.read
      end

      [response, nil]
    end

    def wget url, path
      system(
        'wget',
        '--user-agent=Mozilla/5.0',
        '-O', path,
        url) || raise('wget gave an error')
    end

    def open_uri uri
      URI.open(URI.parse(uri), 'User-Agent' => 'Mozilla/5.0')
    end

    def last_date items
      items.sort_by { |_, data| data['end_on'] }.
        dig(-1, -1, 'end_on').
        strftime('%Y%m%d')
    end

    def write_pack
      paths =
        %w[DataLocal resLocal ImageLocal ImageDataLocal].product(
          ['.list', '.pack']).map(&:join).map do |name|
          "assets/#{name}"
        end

      unzip(*paths) && begin
        assets = Dir["#{app_data_path}/assets/*"]
        FileUtils.mv(assets, app_data_path, verbose: true)
        FileUtils.rmdir("#{app_data_path}/assets", verbose: true)
        true
      end
    end

    def extract_sos_bundle
      path = "#{apk_id}/InstallPack*.apk"

      if unzip(path)
        actual_apk_path = Dir["#{app_data_path}/#{path}"].first
        FileUtils.mv(actual_apk_path, apk_path, verbose: true)
        FileUtils.rmdir("#{app_data_path}/#{apk_id}", verbose: true)
        FileUtils.rmdir(app_data_path, verbose: true)
      else
        raise(VersionNotFound.new("apksos has invalid apk for #{vesion}"))
      end
    end

    def unzip *paths
      require 'fileutils'

      system('unzip', apk_path, *paths, '-d', app_data_path) || begin
        puts "Removing bogus #{apk_path}..."
        FileUtils.rm_r(data_path(version))
        false
      end
    end

    def each_list dir=nil
      root = dir || app_data_path
      ext = File.extname(root)

      if ext.empty?
        Dir["#{root}/**/*.list"].each do |file|
          yield(file)
        end
      else
        yield("#{root.delete_suffix(ext)}.list")
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

    def data_path dir
      "#{Root}/data/#{lang}/#{dir}"
    end

    def event_path
      @event_path ||= data_path('events')
    end

    def app_data_path
      @app_data_path ||= data_path("#{version}/app")
    end

    def apk_path
      @apk_path ||= data_path("#{version}/bc-#{lang}.apk")
    end

    def extract_path
      @extract_path ||= "#{Root}/extract/#{lang}/#{version}"
    end

    def version_id
      @version_id ||= version.split('.').map{|int| sprintf('%02d', int)}.join
    end

    def jwt
      @jwt ||= NyankoAuth.new.generate_jwt(version_id)
    end
  end
end
