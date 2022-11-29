
require_relative '../lib/battle-cats-rolls/root'
require 'fileutils'

%w[en tw jp kr].each do |lang|
  root = "#{BattleCatsRolls::Root}/data/#{lang}"
  apks = Dir["#{root}/*"].filter_map do |dir|
    dir.match?(%r{/(\d+\.)+\d\z}) &&
      File.basename(dir).split('.').map(&:to_i)
  end.sort

  apks[0...-1].each do |version|
    path = version.join('.')
    puts "Removing outdated #{lang}/#{path}"
    FileUtils.rm_r("#{root}/#{path}")
  end
end
