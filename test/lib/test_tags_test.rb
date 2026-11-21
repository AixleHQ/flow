# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class TestTagsTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/test-tags").to_s

  PATHS = { "description" => "d", "rule" => "paths", "paths" => [ "db/migrate/**/*", "db/schema.rb" ] }.freeze
  DEVELOP = { "description" => "d", "rule" => "develop" }.freeze

  test "the committed tags are all valid" do
    tags = TestTags.load

    assert_includes tags.names, "schema_parity"
  end

  test "a pull request leaves out a develop-only tag whatever it changes" do
    tags = TestTags.new("slow" => DEVELOP)

    assert_equal [ "slow" ], tags.excluded_for_pull_request([ "db/schema.rb" ])
    assert_equal [ "slow" ], tags.excluded_for_pull_request([])
  end

  test "a pull request runs a paths tag when a changed file matches a glob, at any depth" do
    tags = TestTags.new("parity" => PATHS)

    assert_empty tags.excluded_for_pull_request([ "app/models/user.rb", "db/migrate/20260101000000_add_x.rb" ])
    assert_empty tags.excluded_for_pull_request([ "db/schema.rb" ])
    assert_equal [ "parity" ], tags.excluded_for_pull_request([ "app/models/user.rb", "db/seeds.rb" ])
  end

  test "an unknown diff leaves nothing out" do
    tags = TestTags.new("slow" => DEVELOP, "parity" => PATHS)

    assert_empty tags.excluded_for_pull_request(nil)
  end

  test "a malformed entry is refused" do
    assert_raises(TestTags::Error) { TestTags.new("Slow" => DEVELOP) }
    assert_raises(TestTags::Error) { TestTags.new("slow" => DEVELOP.merge("description" => " ")) }
    assert_raises(TestTags::Error) { TestTags.new("slow" => DEVELOP.merge("rule" => "nightly")) }
    assert_raises(TestTags::Error) { TestTags.new("slow" => PATHS.merge("paths" => [])) }
  end

  test "excluding a tag nobody defined is refused, so a typo cannot leave a test running or skipped by accident" do
    error = assert_raises(TestTags::Error) { TestTags.excluded_by_environment("TEST_EXCLUDE_TAGS" => "schema_parity shcema_parity") }

    assert_match(/unknown test tag shcema_parity/, error.message)
    assert_equal [ "schema_parity" ], TestTags.excluded_by_environment("TEST_EXCLUDE_TAGS" => "schema_parity")
    assert_empty TestTags.excluded_by_environment({})
  end

  test "bin/test-tags leaves tags out for a pull request only, from the diff against its base" do
    Dir.mktmpdir("test-tags") do |dir|
      git(dir, "init", "-q")
      File.write(File.join(dir, "README.md"), "one\n")
      commit(dir, "first")
      File.write(File.join(dir, "README.md"), "two\n")
      commit(dir, "docs only")

      assert_equal "schema_parity", exclude(dir, "pull_request")
      assert_equal "", exclude(dir, "push")
      assert_equal "", exclude(dir, "workflow_dispatch")

      FileUtils.mkdir_p(File.join(dir, "db/migrate"))
      File.write(File.join(dir, "db/migrate/20260101000000_add_x.rb"), "# migration\n")
      commit(dir, "migration")

      assert_equal "", exclude(dir, "pull_request")
    end
  end

  test "bin/test-tags leaves nothing out when the diff cannot be read" do
    Dir.mktmpdir("test-tags") do |dir|
      assert_equal "", exclude(dir, "pull_request")
    end
  end

  private

  def exclude(dir, event)
    out, err, status = Open3.capture3({ "GITHUB_EVENT_NAME" => nil }, SCRIPT, "exclude", "--event", event, chdir: dir)
    assert status.success?, err
    out.strip
  end

  def git(dir, *args)
    env = { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.test", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.test" }
    out, status = Open3.capture2e(env, "git", *args, chdir: dir)
    assert status.success?, out
  end

  def commit(dir, message)
    git(dir, "add", "-A")
    git(dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", message)
  end
end

class TestTaggingTest < ActiveSupport::TestCase
  test "a class tag leaves out every test of the class, a test tag only that test" do
    klass = build_class do
      tags :schema_parity
      test("a") { nil }
    end
    single = build_class do
      tag :schema_parity
      test("tagged") { nil }
      test("untagged") { nil }
    end
    plain = build_class { test("plain") { nil } }

    with_excluded("schema_parity") do
      assert_empty klass.runnable_methods
      assert_equal [ "test_untagged" ], single.runnable_methods
      assert_equal [ "test_plain" ], plain.runnable_methods
    end
  end

  test "nothing is left out when no tag is excluded" do
    single = build_class do
      tag :schema_parity
      test("tagged") { nil }
    end

    with_excluded("") { assert_equal [ "test_tagged" ], single.runnable_methods }
  end

  test "a subclass inherits its parent's class tags" do
    parent = build_class do
      tags :schema_parity
      test("parent") { nil }
    end
    child = Class.new(parent) { test("child") { nil } }

    with_excluded("schema_parity") { assert_empty child.runnable_methods }
  ensure
    Minitest::Runnable.runnables.delete(child)
  end

  test "tagging with a tag nobody defined is refused" do
    assert_raises(TestTags::Error) { build_class { tags :shcema_parity } }
    assert_raises(TestTags::Error) { build_class { tag :shcema_parity } }
  end

  private

  # A throwaway test class; taken out of Minitest's registry so the suite does not run it.
  def build_class(&block)
    Class.new(ActiveSupport::TestCase, &block).tap { |klass| Minitest::Runnable.runnables.delete(klass) }
  end

  def with_excluded(names)
    previous = ENV["TEST_EXCLUDE_TAGS"]
    ENV["TEST_EXCLUDE_TAGS"] = names
    yield
  ensure
    ENV["TEST_EXCLUDE_TAGS"] = previous
  end
end
