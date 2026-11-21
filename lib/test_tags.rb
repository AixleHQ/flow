# frozen_string_literal: true

require "json"

# The tags a test can carry, and the rule that says when a tagged test runs in CI. The rules
# live in config/test_tags.json, one entry per tag, and nowhere else: the Rails suite
# (test/support/test_tags.rb), the Vitest suite (vitest.config.ts, Makefile) and the CI step
# (bin/test-tags) all read that file. docs/testing.md §9 says how to use it.
#
# Plain Ruby with no gems: bin/test-tags runs on the CI runner, outside the image.
#
# A rule is one of:
#   "push"     the tag runs on pushes only (every event that is not a pull request); a pull
#              request leaves it out.
#   "paths"    the tag runs on pushes, and on a pull request that changes a file matching one of
#              the entry's "paths" globs.
# A test without a tag runs everywhere.
class TestTags
  PATH = File.expand_path("../config/test_tags.json", __dir__)
  RULES = %w[push paths].freeze
  NAME = /\A[a-z][a-z0-9_]*\z/

  Error = Class.new(StandardError)

  # What the Rails and Vitest runs exclude, as a space-separated list of tag names.
  EXCLUDE_VARIABLE = "TEST_EXCLUDE_TAGS"

  def self.load(path = PATH)
    new(JSON.parse(File.read(path)))
  end

  # The tags the current run leaves out (EXCLUDE_VARIABLE), after checking that each is defined.
  def self.excluded_by_environment(env = ENV)
    names = env.fetch(EXCLUDE_VARIABLE, "").split
    load.tap { |tags| tags.validate!(names) }
    names
  end

  attr_reader :entries

  def initialize(entries)
    @entries = entries
    entries.each { |name, entry| check_entry(name, entry) }
  end

  def names
    entries.keys
  end

  def validate!(names)
    unknown = names.map(&:to_s) - self.names
    raise Error, "unknown test tag #{unknown.join(', ')}; the tags are #{self.names.join(', ')} (config/test_tags.json)" if unknown.any?
  end

  # The tags a pull request leaves out. `changed_files` is nil when the diff is unknown, and then
  # nothing is left out: a run that cannot tell what changed runs everything.
  def excluded_for_pull_request(changed_files)
    return [] if changed_files.nil?

    entries.reject { |_name, entry| runs_for?(entry, changed_files) }.keys
  end

  private

  def runs_for?(entry, changed_files)
    entry["rule"] == "paths" && changed_files.any? { |file| matches?(entry["paths"], file) }
  end

  def matches?(globs, file)
    globs.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
  end

  def check_entry(name, entry)
    raise Error, "tag #{name.inspect} is not a lower-case word (letters, digits, underscore)" unless NAME.match?(name)
    raise Error, "tag #{name} has no description" if entry["description"].to_s.strip.empty?
    raise Error, "tag #{name}: rule must be one of #{RULES.join(', ')}" unless RULES.include?(entry["rule"])
    raise Error, "tag #{name}: rule paths needs a non-empty paths list" if entry["rule"] == "paths" && Array(entry["paths"]).empty?
  end
end
