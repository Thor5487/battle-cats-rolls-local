# -*- encoding: utf-8 -*-
# stub: pork 2.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pork".freeze
  s.version = "2.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Lin Jen-Shin (godfat)".freeze]
  s.date = "2022-12-28"
  s.description = "Pork -- Simple and clean and modular testing library.\n\nInspired by [Bacon][].\n\n[Bacon]: https://github.com/chneukirchen/bacon".freeze
  s.email = ["godfat (XD) godfat.org".freeze]
  s.homepage = "https://github.com/godfat/pork".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Pork -- Simple and clean and modular testing library.".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<method_source>.freeze, [">= 0"])
  s.add_development_dependency(%q<ruby-progressbar>.freeze, [">= 0"])
end
