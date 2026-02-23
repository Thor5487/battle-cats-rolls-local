# -*- encoding: binary -*-
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'time'
require 'rack/utils'
require 'rack/mime'
require 'kgio'

class TryGzipStatic
  attr_accessor :root
  class KF < Kgio::File
    # attr_writer :sf_range

    # only used if the server does not handle #to_path,
    # we actually hit this if serving the gzipped file in the first place,
    # _and_ Rack::Deflater is used in the middleware stack.  Oh well...
    def each
      buf = ''.dup
      rsize = 8192
      if @sf_range
        file.seek(@sf_range.begin)
        sf_count = @sf_range.end - @sf_range.begin + 1
        while sf_count > 0
          read(sf_count > rsize ? rsize : sf_count, buf) or break
          sf_count -= buf.size
          yield buf
        end
        raise "file truncated" if sf_count != 0
      else
        yield(buf) while read(rsize, buf)
      end
    end
  end

  def initialize(root, default_type = 'text/plain')
    @root = root.b
    @default_type = default_type
  end

  def fspath(env)
    path_info = Rack::Utils.unescape(env["PATH_INFO"], Encoding::BINARY)
    path_info =~ /\.\./ ? nil : "#@root#{path_info}"
  end

  def get_range(env, path, st)
    if ims = env["HTTP_IF_MODIFIED_SINCE"]
      return [ 304, {}, [] ] if st.mtime.httpdate == ims
    end

    size = st.size
    ranges = byte_ranges(env, size)
    if ranges.nil? || ranges.length > 1
      [ 200 ] # serve the whole thing, possibly with static gzip \o/
    elsif ranges.empty?
      res = r(416)
      res[1]["Content-Range"] = "bytes */#{size}"
      res
    else # partial response, no using static gzip file
      range = ranges[0]
      len = range.end - range.begin + 1
      h = fheader(env, path, st, nil, len)
      h["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{size}"
      [ 206, h, range ]
    end
  end

  def fheader(env, path, st, gz_st = nil, len = nil)
    if path =~ /(.[^.]+)\z/
      mime = Rack::Mime.mime_type($1, @default_type)
    else
      mime = @default_type
    end
    len ||= (gz_st ? gz_st : st).size
    h = {
      "Content-Type" => mime,
      "Content-Length" => len.to_s,
      "Last-Modified" => st.mtime.httpdate,
      "Accept-Ranges" => "bytes",
    }
    h["Cache-Control"] = "no-transform" unless mime =~ %r{\Atext\/}
    if gz_st
      h["Content-Encoding"] = "gzip"
      h["Vary"] = "Accept-Encoding"
    end
    h
  end

  def head_no_gz(res, env, path, st)
    res[1] = fheader(env, path, st)
    res[2] = [] # empty body
    res
  end

  def stat_path(env)
    path = fspath(env) or return r(403)
    begin
      st = File.lstat(path)
      if st.symlink?
        path = File.readlink(path)
        path[0] == '/'.freeze or path = "#@root/#{path}"
        st = File.stat(path)
      end
      return r(404) unless st.file?
      return r(403) unless st.readable?
      [ path, st ]
    rescue Errno::ENOENT, Errno::ENOTDIR
      r(404)
    rescue Errno::EACCES
      r(403)
    rescue => e
      r(500, e, env)
    end
  end

  def head(env)
    path, st = res = stat_path(env)
    return res if Integer === path # integer status code on failure

    # see if it's a range request, no gzipped version if so
    status, _ = res = get_range(env, path, st)
    case status
    when 206
      res[2] = [] # empty body, headers  are all set
      res
    when 200 # fall through to trying gzipped version
      # client requested gzipped path explicitly or did not want gzip
      if path =~ /\.gz\z/i || !want_gzip?(env)
        head_no_gz(res, env, path, st)
      else # try the gzipped version
        begin
          gz_st = File.stat("#{path}.gz")
          if gz_st.mtime == st.mtime
            res[1] = fheader(env, path, st, gz_st)
            res[2] = []
            res
          else
            head_no_gz(res, env, path, st)
          end
        rescue Errno::ENOENT, Errno::EACCES
          head_no_gz(res, env, path, st)
        rescue => e
          r(500, e, env)
        end
      end
    else # 416, 304
      res
    end
  end

  def call(env)
    case env["REQUEST_METHOD"]
    when "GET" then get(env)
    when "HEAD" then head(env)
    else r(405)
    end
  end

  def want_gzip?(env)
    env["HTTP_ACCEPT_ENCODING"] =~ /\bgzip\b/i
  end

  def get(env)
    path, st, _ = res = stat_path(env)
    return res if Integer === path # integer status code on failure

    # see if it's a range request, no gzipped version if so
    status, _, _ = res = get_range(env, path, st)
    case status
    when 206
      res[2] = KF.open(path) # stat succeeded
    when 200
      # client requested gzipped path explicitly or did not want gzip
      if path =~ /\.gz\z/i || !want_gzip?(env)
        res[1] = fheader(env, path, st)
        res[2] = KF.open(path)
      else
        case gzbody = KF.tryopen("#{path}.gz")
        when KF
          gz_st = gzbody.stat
          if gz_st.file? && gz_st.mtime == st.mtime
            # yay! serve the gzipped version as the regular one
            # this should be the most likely code path
            res[1] = fheader(env, path, st, gz_st)
            res[2] = gzbody
          else
            gzbody.close
            res[1] = fheader(env, path, st)
            res[2] = KF.open(path)
          end
        when :ENOENT, :EACCES
          res[1] = fheader(env, path, st)
          res[2] = KF.open(path)
        else
          res = r(500, gzbody.to_s, env)
        end
      end
    end
    res
  rescue Errno::ENOENT # could get here from a race
    r(404)
  rescue Errno::EACCES # could get here from a race
    r(403)
  rescue => e
    r(500, e, env)
  end

  def r(code, exc = nil, env = nil)
    if env && exc && logger = env["rack.logger"]
      msg = exc.message if exc.respond_to?(:message)
      msg = msg.dump if /[[:cntrl:]]/ =~ msg # prevent code injection
      logger.warn("#{env['REQUEST_METHOD']} #{env['PATH_INFO']} " \
                  "#{code} #{msg}")
      if exc.respond_to?(:backtrace) && !(SystemCallError === exc)
        exc.backtrace.each { |line| logger.warn(line) }
      end
    end

    if Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(code)
      [ code, {}, [] ]
    else
      msg = "#{code} #{Rack::Utils::HTTP_STATUS_CODES[code.to_i]}\n"
      h = { 'Content-Type' => 'text/plain', 'Content-Length' => msg.size.to_s }
      [ code, h, [ msg ] ]
    end
  end

  if Rack::Utils.respond_to?(:get_byte_ranges) # rack 2.0+
    def byte_ranges(env, size)
      Rack::Utils.get_byte_ranges(env['HTTP_RANGE'], size)
    end
  else # rack 1.x
    def byte_ranges(env, size); Rack::Utils.byte_ranges(env, size); end
  end
end
