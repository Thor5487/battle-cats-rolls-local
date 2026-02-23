# -*- encoding: utf-8 -*-
# stub: dalli 4.3.3 ruby lib

Gem::Specification.new do |s|
  s.name = "dalli".freeze
  s.version = "4.3.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/petergoldstein/dalli/issues", "changelog_uri" => "https://github.com/petergoldstein/dalli/blob/v4.3/CHANGELOG.md", "rubygems_mfa_required" => "true" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Peter M. Goldstein".freeze, "Mike Perham".freeze]
  s.date = "1980-01-02"
  s.description = "High performance memcached client for Ruby".freeze
  s.email = ["peter.m.goldstein@gmail.com".freeze, "mperham@gmail.com".freeze]
  s.homepage = "https://github.com/petergoldstein/dalli".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "High performance memcached client for Ruby".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<logger>.freeze, [">= 0"])
end
