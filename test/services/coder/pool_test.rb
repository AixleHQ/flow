# frozen_string_literal: true

require "test_helper"

class Coder::PoolTest < ActiveSupport::TestCase
  test "a workspace is in the pool of its prefix when its suffix is one segment" do
    assert Coder::Pool.matches?("aixle", "aixle-1a2b3c4d")
    assert Coder::Pool.matches?("aixle-r", "aixle-r-1a2b3c4d")
  end

  test "a prefix that nests inside another does not take its workspaces" do
    assert_not Coder::Pool.matches?("aixle", "aixle-r-1a2b3c4d")
  end

  test "the match ignores case on both sides" do
    assert Coder::Pool.matches?("aixle", "Aixle-1A2B")
    assert Coder::Pool.matches?("AIXLE", "aixle-1a2b")
  end

  test "workspaces made by hand under another pattern are not in the pool" do
    assert_not Coder::Pool.matches?("aixle", "aixle-prod-a-b")
    assert_not Coder::Pool.matches?("aixle", "aixle")
    assert_not Coder::Pool.matches?("aixle", "aixle-")
    assert_not Coder::Pool.matches?("aixle", "other-1a2b3c4d")
  end

  test "a blank prefix is the legacy pool of every workspace" do
    assert Coder::Pool.matches?("", "anything-at-all")
    assert Coder::Pool.matches?(nil, "x")
  end

  test "a prefix is lowercase letters, digits and inner hyphens, at most 23 characters" do
    assert Coder::Pool.valid_prefix?("aixle")
    assert Coder::Pool.valid_prefix?("my-project-2")
    assert Coder::Pool.valid_prefix?("a" * 23)
    assert_not Coder::Pool.valid_prefix?("a" * 24)
    assert_not Coder::Pool.valid_prefix?("")
    assert_not Coder::Pool.valid_prefix?("aixle-")
    assert_not Coder::Pool.valid_prefix?("-aixle")
    assert_not Coder::Pool.valid_prefix?("Aixle")
    assert_not Coder::Pool.valid_prefix?("aixle_prod")
  end

  test "a generated name fits Coder's limit and is in its own pool" do
    name = Coder::Pool.generate_name("a" * 23)

    assert_equal 32, name.length
    assert Coder::Pool.matches?("a" * 23, name)
  end

  test "suggest_prefix makes a valid prefix out of a project or company name" do
    assert_equal "my-project", Coder::Pool.suggest_prefix("My Project")
    assert_equal "acme-co-eu", Coder::Pool.suggest_prefix("  Acme & Co. (EU)!  ")
    assert_equal "ab-c", Coder::Pool.suggest_prefix("ab---c")
    suggestion = Coder::Pool.suggest_prefix("A very long project name that goes on and on")
    assert_operator suggestion.length, :<=, 23
    assert Coder::Pool.valid_prefix?(suggestion)
    assert_equal "", Coder::Pool.suggest_prefix("***")
  end
end
