# frozen_string_literal: true

require "test_helper"

# The reference is what the Aixle Builder and personal-MCP callers read about the
# platform. It went stale for months once (a step field that no longer existed,
# renamed tools), so the facts it states are pinned to the code here.
class AixleSystemReferenceTest < ActiveSupport::TestCase
  REFERENCE = Rails.root.join("references/aixle-system-reference.md").read.freeze

  STEP_COLUMNS_NOT_DOCUMENTED = %w[id workflow_id created_at updated_at deleted_at].freeze

  test "documents every step field" do
    missing = Step.column_names - STEP_COLUMNS_NOT_DOCUMENTED - documented_names

    assert_empty missing, "references/aixle-system-reference.md does not document step fields: #{missing.join(', ')}"
  end

  test "documents every workflow config key, runtime, gate type, trigger kind, preset and integration" do
    facts = Workflow::ALLOWED_CONFIG_KEYS +
            ContainerStrategies::AgentBaseStrategy::VALID_AGENT_TYPES +
            Step::SUPPORTED_AGENT_RUNTIMES +
            Gate.gate_type.values +
            PersonalTools::WorkflowTriggerSupport::KINDS +
            BoardPresets::PRESETS.keys.map(&:to_s) +
            Integration.provider.values

    missing = facts.uniq.reject { |fact| REFERENCE.include?(fact) }

    assert_empty missing, "references/aixle-system-reference.md does not mention: #{missing.join(', ')}"
  end

  test "names only tools that exist" do
    tool_names = Tools::Registry.definitions.values.map { |d| d.name.to_s }
    named = REFERENCE.scan(/`([a-z]+(?:_[a-z]+)+)`/).flatten.uniq
    enum_values = PersonalTools::WorkflowTriggerSupport::SUBJECT_POLICIES
    tool_like = named.select { |n| n.match?(/\A(get|list|create|update|delete|install|search|setup|duplicate|board|finish|fail|mark|promote|share|read|refresh)_/) } - enum_values

    assert_empty tool_like - tool_names, "the reference names tools that do not exist"
  end

  test "carries none of the names that went stale" do
    %w[mount_repositories board_create_wait meta_ bmad-llms-full].each do |stale|
      assert_not_includes REFERENCE, stale
    end
  end

  private

  def documented_names
    REFERENCE.scan(/`([a-z_]+)`/).flatten
  end
end
