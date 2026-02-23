# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
$stdout.sync = $stderr.sync = Thread.abort_on_exception = true
$-w = true if RUBY_VERSION.to_f >= 2.0
require 'thread'
require 'fileutils'

def rubyv
  puts RUBY_DESCRIPTION
end

# Global Test Lock, to protect:
#   Process.wait*, Dir.chdir, ENV, trap, require, etc...
GTL = Mutex.new

# fork-aware coverage data gatherer, see also test/covshow.rb
if ENV["COVERAGE"]
  require "coverage"
  COVMATCH = %r{(/lib/yahns\b|extras/).*rb\z}
  COVDUMPFILE = File.expand_path("coverage.dump")

  def __covmerge
    res = Coverage.result

    # do not create the file, Makefile does this before any tests run
    File.open(COVDUMPFILE, IO::RDWR) do |covtmp|
      covtmp.binmode
      covtmp.sync = true

      # we own this file (at least until somebody tries to use NFS :x)
      covtmp.flock(File::LOCK_EX)

      prev = covtmp.read
      prev = prev.empty? ? {} : Marshal.load(prev)
      res.each do |filename, counts|
        # filter out stuff that's not in our project
        COVMATCH =~ filename or next

        # For compatibility with https://bugs.ruby-lang.org/issues/9508
        # TODO: support those features if that gets merged into mainline
        unless Array === counts
          counts = counts[:lines]
        end

        merge = prev[filename] || []
        merge = merge
        counts.each_with_index do |count, i|
          count or next
          merge[i] = (merge[i] || 0) + count
        end
        prev[filename] = merge
      end
      covtmp.rewind
      covtmp.truncate(0)
      covtmp.write(Marshal.dump(prev))
      covtmp.flock(File::LOCK_UN)
    end
  end

  Coverage.start
  # we need to nest at_exit to fire after minitest runs
  at_exit { at_exit { __covmerge } }
end

gem 'minitest'
begin # favor minitest 5
  require 'minitest'
  Testcase = Minitest::Test
  mtobj = Minitest
rescue NameError, LoadError # but support minitest 4
  require 'minitest/unit'
  Testcase = Minitest::Unit::TestCase
  mtobj = MiniTest::Unit.new
end

# Not using minitest/autorun because that doesn't guard against redundant
# extra runs with fork.  We cannot use exit! in the tests either
# (since users/apps hosted on yahns _should_ expect exit, not exit!).
TSTART_PID = $$
at_exit do
  # skipping @@after_run stuff in minitest since we don't need it
  case $!
  when nil, SystemExit
    exit(mtobj.run(ARGV)) if $$ == TSTART_PID
  end
end

require "tempfile"
require 'tmpdir'

# Can't rely on mktmpdir until we drop Ruby 1.9.3 support
def yahns_mktmpdir
  d = nil
  begin
    dir = "#{Dir.tmpdir}/yahns.#$$.#{rand}"
    Dir.mkdir(dir)
    d = dir
  rescue Errno::EEXIST
  end until d
  return d unless block_given?
  begin
    yield d
  ensure
    FileUtils.remove_entry(d)
  end
end

def tmpfile(*args)
  tmp = Tempfile.new(*args)
  tmp.sync = true
  tmp.binmode
  tmp
end

require 'io/wait'
# needed for Rubinius 2.0.0, we only use IO#nread in tests
class IO
  # this ignores buffers
  def nread
    buf = "\0" * 8
    ioctl(0x541B, buf)
    buf.unpack("l_")[0]
  end
end if ! IO.method_defined?(:nread) && RUBY_PLATFORM =~ /linux/

def cloexec_pipe
  IO.pipe
end

def require_exec(cmd)
  ENV["PATH"].split(/:/).each do |path|
    return true if File.executable?("#{path}/#{cmd}")
  end
  skip "#{cmd} not found in PATH"
  false
end

def xfork
  GTL.synchronize { fork { yield } }
end

class DieIfUsed
  @@n = 0
  def each
    abort "body.each called after response hijack\n"
  end

  def close
    warn "INFO #$$ closed DieIfUsed #{@@n += 1}\n"
  end
end

# tricky to test output buffering behavior across different OSes
def skip_skb_mem
  return if ENV['YAHNS_TEST_FORCE']
  skip "linux-only test" unless RUBY_PLATFORM =~ /linux/
  [ [ '/proc/sys/net/ipv4/tcp_rmem', "4096	87380	6291456\n" ],
    [ '/proc/sys/net/ipv4/tcp_wmem', "4096	16384	4194304\n" ]
  ].each do |file, expect|
    val = File.read(file)
    val == expect or skip "#{file} had: #{val}expected: #{expect}"
  end
end

require 'yahns'

# needed for parallel (MT) tests)
require 'yahns/rack'
