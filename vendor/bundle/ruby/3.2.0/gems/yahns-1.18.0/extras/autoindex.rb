# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'time'
require 'rack/utils'
require 'rack/request'

# this is middleware meant to behave like "index" and "autoindex" in nginx
# No CSS or JS to avoid potential security bugs
# Only basic pre-formatted HTML, not even tables, should look good in lynx
# all bikeshedding here :>
class Autoindex
  FN = %{<a href="%s">%s</a>}
  TFMT = "%Y-%m-%d %H:%M"

  # default to a dark, web-safe (216 color) palette for power-savings.
  # Color-capable browsers can respect the prefers-color-scheme:light
  # @media query (browser support a work-in-progress)
  STYLE = <<''.gsub(/^\s*/m, '').delete!("\n")
@media screen {
  *{background:#000;color:#ccc}
  a{color:#69f;text-decoration:none}
  a:visited{color:#96f}
}
@media screen AND (prefers-color-scheme:light) {
  *{background:#fff;color:#333}
  a{color:#00f;text-decoration:none}
  a:visited{color:#808}
}

  def initialize(app, *args)
    app.respond_to?(:root) or raise ArgumentError,
       "wrapped app #{app.inspect} does not respond to #root"
    @app = app
    @root = app.root

    @index = case args[0]
    when Array then args.shift
    when String then Array(args.shift)
    else
      %w(index.html)
    end

    @skip_gzip_static = @skip_dotfiles = nil
    case args[0]
    when Hash
      @skip_gzip_static = args[0][:skip_gzip_static]
      @skip_dotfiles = args[0][:skip_dotfiles]
    when true, false
      @skip_gzip_static = args.shift
    end
    @skip_gzip_static = true if @skip_gzip_static.nil?
    @skip_dotfiles = false if @skip_dotfiles.nil?
  end

  def redirect_slash(env)
    req = Rack::Request.new(env)
    location = "#{req.url}/"
    body = "Redirecting to #{location}\n"
    [ 302,
      {
        "Content-Type" => "text/plain",
        "Location" => location,
        "Content-Length" => body.size.to_s
      },
     [ body ] ]
  end

  def call(env)
    case env["REQUEST_METHOD"]
    when "GET", "HEAD"
      # try to serve the static file, first
      status, _, body = res = @app.call(env)
      return res if status.to_i != 404

      path_info = env["PATH_INFO"]
      path_info_ue = Rack::Utils.unescape(path_info, Encoding::BINARY)

      # reject requests to go up a level (browser takes care of it)
      path_info_ue =~ /\.\./ and return r(403)

      # cleanup the path
      path_info_ue.squeeze!('/')

      # will raise ENOENT/ENOTDIR
      pfx = "#@root#{path_info_ue}"
      dir = Dir.open(pfx)

      return redirect_slash(env) unless path_info =~ %r{/\z}

      # try index.html and friends
      tryenv = env.dup
      @index.each do |base|
        tryenv["PATH_INFO"] = "#{path_info}#{base}"
        status, _, body = res = @app.call(tryenv)
        return res if status.to_i != 404
      end

      # generate the index, show directories first
      dirs = []
      files = []
      ngz_idx = {} if @skip_gzip_static # used to avoid redundant stat()
      dir.each do |base|
        case base
        when "."
          next
        when ".."
          next if path_info == "/"
        when /\A\./
          next if @skip_dotfiles
        end

        begin
          st = File.stat("#{pfx}#{base}")
        rescue
          next
        end

        url = Rack::Utils.escape_html(Rack::Utils.escape(base))
        name = Rack::Utils.escape_html(base)
        if st.directory?
          name << "/"
          url << "/"
        end
        entry = sprintf(FN, url, name)
        pad = 52 - name.size
        entry << (" " * pad) if pad > 0
        entry << st.mtime.strftime(TFMT)
        entry << sprintf("% 8s", human_size(st))
        entry = [name, entry]

        if st.directory?
          dirs << entry
        elsif ngz_idx
          ngz_idx[name] = entry
        else
          files << entry
        end
      end

      if ngz_idx
        ngz_idx.each do |name, entry|
          # n.b: use use dup.sub! to ensure ngz_path is nil
          # if .gz is not found
          ngz_path = name.dup.sub!(/\.gz\z/, '')
          ngz_idx.include?(ngz_path) or files << entry
        end
      end

      dirs.sort! { |(a,_),(b)| a <=> b }.map! { |(_,ent)| ent }
      files.sort! { |(a,_),(b)| a <=> b }.map! { |(_,ent)| ent }

      path_info_html = path_info_ue.split(%r{/}, -1).map! do |part|
        Rack::Utils.escape_html(part)
      end.join("/")
      body = "<html><head><title>Index of #{path_info_html}</title>" \
             "<style>#{STYLE}</style>" \
             "</head><body><h1>Index of #{path_info_html}</h1><hr><pre>\n" \
             "#{dirs.concat(files).join("\n")}" \
             "</pre><hr></body></html>\n"
      h = { "Content-Type" => "text/html", "Content-Length" => body.size.to_s }
      [ 200, h, [ body ] ]
    else
      r(405)
    end
  rescue Errno::ENOENT, Errno::ENOTDIR # from Dir.open
    r(404)
  rescue => e
    r(500, e, env)
  ensure
    dir.close if dir
  end

  def r(code, exc = nil, env = nil)
    if env && exc && logger = env["rack.logger"]
      msg = exc.message
      msg = msg.dump if /[[:cntrl:]]/ =~ msg # prevent code injection
      logger.warn("#{env['REQUEST_METHOD']} #{env['PATH_INFO']} " \
                  "#{code} #{msg}")
      exc.backtrace.each { |line| logger.warn(line) }
    end

    if Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(code)
      [ code, {}, [] ]
    else
      msg = "#{code} #{Rack::Utils::HTTP_STATUS_CODES[code.to_i]}\n"
      h = { 'Content-Type' => 'text/plain', 'Content-Length' => msg.size.to_s }
      [ code, h, [ msg ] ]
    end
  end

  def human_size(st)
    if st.file?
      size = st.size
      suffix = ""
      %w(K M G T).each do |s|
        break if size < 1024
        size /= 1024.0
        if size <= 1024
          suffix = s
          break
        end
      end
      "#{size.round}#{suffix}"
    else
      "-"
    end
  end
end
