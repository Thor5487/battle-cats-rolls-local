# Copyright (C) all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
Gem::Specification.new do |s|
  manifest = File.read('.gem-manifest').split(/\n/)
  s.name = %q{yahns}
  s.version = ENV["VERSION"].dup
  s.authors = ["yahns hackers"]
  s.summary = "sleepy, multi-threaded, non-blocking application server"
  s.description = File.read("README").split(/\n\n/)[1].strip
  s.email = %q{yahns-public@yhbt.net}
  s.executables = manifest.grep(%r{\Abin/}).map { |s| s.sub(%r{\Abin/}, "") }
  s.files = manifest

  s.required_ruby_version = '>= 2.0'

  s.add_dependency(%q<kgio>, '~> 2.9')
  s.add_dependency(%q<sleepy_penguin>, '~> 3.2')
  s.add_dependency(%q<unicorn>, '>= 4.6.3', '< 7.0')
  # s.add_dependency(%q<kgio-sendfile>, '~> 1.2') # optional

  # minitest is standard in Ruby 2.0, 4.3 is packaged with Ruby 2.0.0,
  # 4.7.5 with 2.1.  We work with minitest 5, too.  6.x does not exist
  # at the time of this writing.  We should always be compatible with
  # minitest (or test-unit) library packaged with the latest official
  # Matz Ruby release.
  s.add_development_dependency(%q<minitest>, '>= 4.3', '< 6.0')

  # for Rack::Utils::HeaderHash#each
  s.add_development_dependency(%q<rack>, '>= 1.1')

  s.homepage = 'https://yhbt.net/yahns.git/about/'
  s.licenses = "GPL-3.0+"
end
