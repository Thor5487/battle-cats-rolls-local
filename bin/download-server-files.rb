
require_relative '../lib/battle-cats-rolls/root'
require_relative '../lib/battle-cats-rolls/aws_cf'
require 'fileutils'

%w[
  5_0
  5_1
  5_2
  070000_03_00
  7_4
  5_5
  5_6
  070000_07_01
  1_8
  070000_09_00
  070100_10_00
  080700_11_01
  090000_12_03
  090400_13_00
  090900_14_00
  100000_15_01
  100300_16_00
  100300_17_01
  100900_18_00
  100900_19_01
  110100_20_00
  110100_21_01
].each do |version|
  dir = "#{BattleCatsRolls::Root}/extract/server_files"
  FileUtils.mkdir_p(dir)

  filename = "battlecats_#{version}.zip"
  path = "#{dir}/#{filename}"

  next if File.exist?(path)

  url = "https://nyanko-assets.ponosgames.com/iphone/battlecats/download/#{filename}"
  signed_url = BattleCatsRolls::AwsCf.new(url).generate

  if !system('wget', '-O', path, signed_url)
    FileUtils.rm(path)
  end
end
