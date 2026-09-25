# frozen_string_literal: true

require "test_helper"

# Every column of a versioned table is either snapshotted or explicitly left out.
# A new column fails here until someone decides which — so it can neither
# silently fall out of history nor (for a credential) silently fall into it.
class Versions::SnapshotCompletenessTest < ActiveSupport::TestCase
  SERIALIZERS = {
    Agent => Versions::Snapshots::Agent,
    Skill => Versions::Snapshots::Skill,
    Tool => Versions::Snapshots::Tool,
    MCPServer => Versions::Snapshots::MCPServer,
    Workflow => Versions::Snapshots::Workflow
  }.freeze

  SERIALIZERS.each do |model, serializer|
    test "#{model.name} columns are all classified" do
      assert_classified model, serializer::FIELDS, serializer::EXCLUDED
    end
  end

  test "step and sub-step columns are all classified" do
    assert_classified Step, Versions::Snapshots::Workflow::STEP_FIELDS, Versions::Snapshots::Workflow::STEP_EXCLUDED
    assert_classified SubStep, Versions::Snapshots::Workflow::SUB_STEP_FIELDS,
                      Versions::Snapshots::Workflow::SUB_STEP_EXCLUDED
  end

  test "tool file columns are all classified" do
    assert_classified ToolFile, Versions::Snapshots::Tool::FILE_FIELDS, Versions::Snapshots::Tool::FILE_EXCLUDED
  end

  private

  def assert_classified(model, fields, excluded)
    unclassified = model.column_names - fields - excluded
    stale = (fields + excluded) - model.column_names
    assert_empty unclassified, "#{model.name}: add these columns to the snapshot FIELDS or EXCLUDED"
    assert_empty stale, "#{model.name}: these classified columns no longer exist"
    assert_empty fields & excluded, "#{model.name}: a column is both snapshotted and excluded"
  end
end
