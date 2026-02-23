# -*- encoding: utf-8 -*-
# stub: sleepy_penguin 3.5.2 ruby lib
# stub: ext/sleepy_penguin/extconf.rb

Gem::Specification.new do |s|
  s.name = "sleepy_penguin".freeze
  s.version = "3.5.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["sleepy_penguin hackers".freeze]
  s.date = "2020-02-01"
  s.description = "sleepy_penguin provides access to newer, Linux-only system calls to wait\non events from traditionally non-I/O sources.  Bindings to the eventfd,\ntimerfd, inotify, and epoll interfaces are provided.  Experimental support\nfor kqueue on FreeBSD (and likely OpenBSD/NetBSD) is also provided.".freeze
  s.email = "sleepy-penguin@yhbt.net".freeze
  s.extensions = ["ext/sleepy_penguin/extconf.rb".freeze]
  s.extra_rdoc_files = ["LICENSE".freeze, "README".freeze, "TODO".freeze, "NEWS".freeze, "ext/sleepy_penguin/epoll.c".freeze, "ext/sleepy_penguin/eventfd.c".freeze, "ext/sleepy_penguin/init.c".freeze, "ext/sleepy_penguin/inotify.c".freeze, "ext/sleepy_penguin/timerfd.c".freeze, "ext/sleepy_penguin/kqueue.c".freeze, "ext/sleepy_penguin/splice.c".freeze]
  s.files = ["LICENSE".freeze, "NEWS".freeze, "README".freeze, "TODO".freeze, "ext/sleepy_penguin/epoll.c".freeze, "ext/sleepy_penguin/eventfd.c".freeze, "ext/sleepy_penguin/extconf.rb".freeze, "ext/sleepy_penguin/init.c".freeze, "ext/sleepy_penguin/inotify.c".freeze, "ext/sleepy_penguin/kqueue.c".freeze, "ext/sleepy_penguin/splice.c".freeze, "ext/sleepy_penguin/timerfd.c".freeze]
  s.homepage = "https://yhbt.net/sleepy_penguin/".freeze
  s.licenses = ["LGPL-2.1+".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Linux I/O events for Ruby".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.0"])
  s.add_development_dependency(%q<strace_me>.freeze, ["~> 1.0"])
end
