# -*- encoding: binary -*-
# Copyright (C) 2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

class Yahns::ChunkBody # :nodoc:
  def initialize(body, vec)
    @body = body
    @vec = vec
  end

  def each
    vec = @vec
    vec[2] = "\r\n".freeze
    @body.each do |chunk|
      vec[0] = "#{chunk.bytesize.to_s(16)}\r\n"
      vec[1] = chunk
      # vec[2] never changes: "\r\n" above
      yield vec
    end
    vec.clear
    yield "0\r\n\r\n".freeze
  end

  def close
    @body.close if @body.respond_to?(:close)
  end
end
