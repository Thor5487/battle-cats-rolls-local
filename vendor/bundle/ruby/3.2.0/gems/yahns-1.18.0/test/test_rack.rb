# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'
require 'rack/lobster'
require 'yahns/rack'
class TestRack < Testcase
  ENV["N"].to_i > 1 and parallelize_me!

  def test_rack
    tmp = tmpfile(%W(config .ru))
    tmp.write "run Rack::Lobster.new\n"
    rapp = GTL.synchronize { Yahns::Rack.new(tmp.path) }
    assert_kind_of Rack::Lobster, GTL.synchronize { rapp.app_after_fork }
    defaults = rapp.app_defaults
    assert_kind_of Hash, defaults
    tmp.close!
  end

  def test_rack_preload
    tmp = tmpfile(%W(config .ru))
    tmp.write "run Rack::Lobster.new\n"
    rapp = GTL.synchronize { Yahns::Rack.new(tmp.path, preload: true) }
    assert_kind_of Rack::Lobster, rapp.instance_variable_get(:@app)
    defaults = rapp.app_defaults
    assert_kind_of Hash, defaults
    tmp.close!
  end
end
