# frozen_string_literal: true

require "test_helper"

class Tools::ReconcilerTest < ActiveSupport::TestCase
  test "first run materializes a shadow row per definition" do
    assert_equal 0, Tool.code_source.count

    assert Tools::Reconciler.run!

    assert_equal Tools::Registry.names.sort, Tool.code_source.not_deleted.pluck(:name).sort
    slack = Tool.code_source.find_by!(name: "slack_post_message")
    assert_equal "workflow", slack.kind.to_s
    assert_equal "app", slack.execution_mode.to_s
    assert_equal "slack", slack.requires_integration
    assert_equal %w[messaging slack], slack.tags
    assert slack.enabled?
    meta = Tool.code_source.find_by!(name: "meta_create_tool")
    assert_not meta.user_attachable
  end

  test "steady-state run is write-free" do
    Tools::Reconciler.run!
    updated_stamps = Tool.code_source.order(:name).pluck(:updated_at)

    Tools::Reconciler.run!

    assert_equal updated_stamps, Tool.code_source.order(:name).pluck(:updated_at)
  end

  test "converges a drifted shadow row back to the definition" do
    Tools::Reconciler.run!
    row = Tool.code_source.find_by!(name: "read_tool_result")
    row.update_columns(display_name: "Hand-edited", input_schema: { "type" => "object" })

    Tools::Reconciler.run!

    row.reload
    assert_equal "Read Tool Result", row.display_name
    assert_equal Tools::Registry.fetch("read_tool_result").input_schema.as_json, row.input_schema.as_json
  end

  test "soft-deletes rows whose definition was removed, never destroys" do
    Tools::Reconciler.run!
    orphan = Tool.code_source.find_by!(name: "finish_session")
    orphan.update_columns(name: "tool_removed_from_code")

    Tools::Reconciler.run!

    orphan.reload
    assert orphan.deleted?
    assert_not orphan.enabled?
    # finish_session itself is re-materialized under its real name
    assert Tool.code_source.not_deleted.exists?(name: "finish_session")
  end

  test "preserves a manual admin disable across reconciles" do
    Tools::Reconciler.run!
    row = Tool.code_source.find_by!(name: "board_list_tasks")
    row.update_columns(enabled: false)

    Tools::Reconciler.run!

    assert_not row.reload.enabled?
  end

  test "resurrects a soft-deleted row when its definition returns" do
    Tools::Reconciler.run!
    row = Tool.code_source.find_by!(name: "board_get_task")
    row.update_columns(deleted_at: Time.current)

    Tools::Reconciler.run!

    assert_nil row.reload.deleted_at
  end

  test "shadow_for materializes the row on demand before any reconcile ran" do
    definition = Tools::Registry.fetch("mark_sub_step")
    assert_equal 0, Tool.code_source.count

    row = Tool.shadow_for(definition)

    assert row.persisted?
    assert_equal "mark_sub_step", row.name
    assert_equal "code", row.source
  end
end
