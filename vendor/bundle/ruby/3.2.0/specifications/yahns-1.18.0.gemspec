# -*- encoding: utf-8 -*-
# stub: yahns 1.18.0 ruby lib

Gem::Specification.new do |s|
  s.name = "yahns".freeze
  s.version = "1.18.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["yahns hackers".freeze]
  s.date = "2021-10-09"
  s.description = "A Free Software, multi-threaded, non-blocking network application server\ndesigned for low _idle_ power consumption.  It is primarily optimized\nfor applications with occasional users which see little or no traffic.\nyahns currently hosts Rack/HTTP applications, but may eventually support\nother application types.  Unlike some existing servers, yahns is\nextremely sensitive to fatal bugs in the applications it hosts.".freeze
  s.email = "yahns-public@yhbt.net".freeze
  s.executables = ["yahns".freeze, "yahns-rackup".freeze]
  s.files = ["bin/yahns".freeze, "bin/yahns-rackup".freeze]
  s.homepage = "https://yhbt.net/yahns.git/about/".freeze
  s.licenses = ["GPL-3.0+".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "sleepy, multi-threaded, non-blocking application server".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<kgio>.freeze, ["~> 2.9"])
  s.add_runtime_dependency(%q<sleepy_penguin>.freeze, ["~> 3.2"])
  s.add_runtime_dependency(%q<unicorn>.freeze, [">= 4.6.3", "< 7.0"])
  s.add_development_dependency(%q<minitest>.freeze, [">= 4.3", "< 6.0"])
  s.add_development_dependency(%q<rack>.freeze, [">= 1.1"])
end
