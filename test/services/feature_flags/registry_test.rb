# frozen_string_literal: true

require "test_helper"

class FeatureFlags::RegistryTest < ActiveSupport::TestCase
  VALID = {
    "description" => "AI summary panel on the board task drawer.",
    "owner" => "@AixleHQ/board",
    "kind" => "release",
    "scope" => "company",
    "default" => false,
    "remove_by" => Date.new(2027, 1, 31)
  }.freeze

  def registry(entries) = FeatureFlags::Registry.new(entries, source: "test registry")

  def invalid(entries)
    assert_raises(FeatureFlags::InvalidRegistry) { registry(entries) }.message
  end

  test "the shipped registry loads, and is empty" do
    registry = FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH)

    assert_predicate registry, :empty?
    assert_empty registry.keys
  end

  test "an empty or comment-only file is an empty registry" do
    Tempfile.create([ "feature_flags", ".yml" ]) do |file|
      file.write("# nothing declared yet\n")
      file.flush

      assert_predicate FeatureFlags::Registry.load(file.path), :empty?
    end
  end

  test "loads a declaration with its attributes, frozen" do
    registry = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)
    flag = registry.fetch(:board_ai_summary)

    assert_equal %i[board_ai_summary coder_reap], registry.keys
    assert_equal [ :release, :company, false, true, Date.new(2027, 1, 31) ],
                 [ flag.kind, flag.scope, flag.default, flag.client?, flag.remove_by ]
    assert_equal "FEATURE_BOARD_AI_SUMMARY", flag.env_var
    assert_predicate flag, :company_scoped?
    assert_predicate registry.fetch("coder_reap"), :global?
    refute_predicate registry.fetch(:coder_reap), :client?
    assert_predicate registry, :frozen?
    assert_raises(FrozenError) { flag.description << "!" }
  end

  test "an undeclared key raises UnknownFlag" do
    assert_raises(FeatureFlags::UnknownFlag) { registry({}).fetch(:board_ai_summary) }
  end

  test "keys must be snake_case" do
    %w[BoardAiSummary board-ai-summary 1st_flag _flag].each do |key|
      assert_match "#{key}: key must match", invalid(key => VALID)
    end
  end

  test "keys may not map to the reserved FEATURE_FLAGS_* prefix" do
    %w[flags flags_refresh_interval].each do |key|
      assert_match "#{key}: key maps to the reserved FEATURE_FLAGS_* prefix", invalid(key => VALID)
    end
    assert registry("flagship" => VALID).declared?(:flagship)
  end

  test "description, owner, kind, scope and default are required" do
    %w[description owner kind scope default].each do |attribute|
      assert_match "board_ai_summary: missing #{attribute}", invalid("board_ai_summary" => VALID.except(attribute))
    end
  end

  test "a release flag needs remove_by; an ops flag does not" do
    assert_match "remove_by (YYYY-MM-DD) is required for kind: release",
                 invalid("board_ai_summary" => VALID.except("remove_by"))
    assert registry("coder_reap" => VALID.except("remove_by").merge("kind" => "ops")).declared?(:coder_reap)
  end

  test "attribute values are checked" do
    {
      { "kind" => "entitlement" } => "kind must be one of release, ops",
      { "scope" => "user" } => "scope must be one of company, global",
      { "default" => "false" } => "default must be true or false",
      { "client" => "yes please" } => "client must be true or false",
      { "description" => "  " } => "description must be text",
      { "owner" => 42 } => "owner must be text",
      { "remove_by" => "soon" } => "remove_by (YYYY-MM-DD) is required",
      { "introduced" => "last week" } => "introduced must be a date",
      { "rollout" => 50 } => "unknown attribute rollout"
    }.each do |change, message|
      assert_match message, invalid("board_ai_summary" => VALID.merge(change))
    end
  end

  test "every problem is listed at once" do
    message = invalid("Bad" => VALID, "board_ai_summary" => VALID.except("owner"), "coder_reap" => "on")

    assert_match "test registry is invalid", message
    assert_match "Bad: key must match", message
    assert_match "board_ai_summary: missing owner", message
    assert_match "coder_reap: must be a mapping of attributes", message
  end

  test "a file that is not a mapping, or not YAML, is invalid" do
    assert_match "must be a mapping of flag keys", invalid([ "board_ai_summary" ])

    Tempfile.create([ "feature_flags", ".yml" ]) do |file|
      file.write("board_ai_summary: [\n")
      file.flush

      assert_raises(FeatureFlags::InvalidRegistry) { FeatureFlags::Registry.load(file.path) }
    end
  end
end
