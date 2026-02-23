# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'helper'

class TestFdmap < Testcase
  def test_fdmap_negative
    fdmap = Yahns::Fdmap.new(Logger.new($stderr), -5)
    nr = fdmap.instance_variable_get :@client_expire_threshold
    assert_operator nr, :>, 0
    assert_equal nr, Process.getrlimit(:NOFILE)[0] - 5
  end

  def test_fdmap_float
    fdmap = Yahns::Fdmap.new(Logger.new($stderr), 0.5)
    nr = fdmap.instance_variable_get :@client_expire_threshold
    assert_operator nr, :>, 0
    assert_equal nr, Process.getrlimit(:NOFILE)[0]/2
  end
end
