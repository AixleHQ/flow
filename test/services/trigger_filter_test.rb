# frozen_string_literal: true

require "test_helper"

class TriggerFilterTest < ActiveSupport::TestCase
  test "empty predicate matches anything" do
    assert TriggerFilter.match?({}, { "a" => 1 })
    assert TriggerFilter.match?(nil, {})
  end

  test "scalar value is an equality match (back-compat)" do
    assert TriggerFilter.match?({ "channel" => "C1" }, { "channel" => "C1" })
    assert_not TriggerFilter.match?({ "channel" => "C1" }, { "channel" => "C2" })
  end

  test "all conditions are AND-ed" do
    pred = { "channel" => "C1", "user" => "U9" }
    assert TriggerFilter.match?(pred, { "channel" => "C1", "user" => "U9" })
    assert_not TriggerFilter.match?(pred, { "channel" => "C1", "user" => "U0" })
  end

  test "dot-path resolves nested fields" do
    pred = { "repository.name" => "palad-app" }
    assert TriggerFilter.match?(pred, { "repository" => { "name" => "palad-app" } })
    assert_not TriggerFilter.match?(pred, { "repository" => { "name" => "other" } })
    assert_not TriggerFilter.match?(pred, { "repository" => "not-a-hash" })
  end

  test "contains / starts_with / ends_with operators" do
    assert TriggerFilter.match?({ "text" => { "op" => "contains", "value" => "ship" } }, { "text" => "please ship it" })
    assert_not TriggerFilter.match?({ "text" => { "op" => "contains", "value" => "ship" } }, { "text" => "hold" })
    assert TriggerFilter.match?({ "ref" => { "op" => "starts_with", "value" => "refs/heads/" } }, { "ref" => "refs/heads/main" })
    assert TriggerFilter.match?({ "ref" => { "op" => "ends_with", "value" => "/main" } }, { "ref" => "refs/heads/main" })
  end

  test "ne / present / blank / in operators" do
    assert TriggerFilter.match?({ "conclusion" => { "op" => "ne", "value" => "failure" } }, { "conclusion" => "success" })
    assert TriggerFilter.match?({ "pr" => { "op" => "present" } }, { "pr" => 42 })
    assert TriggerFilter.match?({ "pr" => { "op" => "blank" } }, { "pr" => "" })
    assert TriggerFilter.match?({ "branch" => { "op" => "in", "value" => %w[main develop] } }, { "branch" => "develop" })
    assert_not TriggerFilter.match?({ "branch" => { "op" => "in", "value" => %w[main develop] } }, { "branch" => "feature" })
  end

  test "numeric comparisons" do
    assert TriggerFilter.match?({ "size" => { "op" => "gt", "value" => 100 } }, { "size" => 150 })
    assert_not TriggerFilter.match?({ "size" => { "op" => "gt", "value" => 100 } }, { "size" => 50 })
    assert_not TriggerFilter.match?({ "size" => { "op" => "gt", "value" => 100 } }, { "size" => "not-a-number" })
  end

  test "regex operator is safe against invalid patterns" do
    assert TriggerFilter.match?({ "text" => { "op" => "regex", "value" => "^ship\\b" } }, { "text" => "ship it" })
    assert_not TriggerFilter.match?({ "text" => { "op" => "regex", "value" => "[" } }, { "text" => "anything" })
  end

  test "unknown operator does not match" do
    assert_not TriggerFilter.match?({ "x" => { "op" => "nonsense", "value" => 1 } }, { "x" => 1 })
  end
end
