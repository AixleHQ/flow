# frozen_string_literal: true

require "test_helper"

class Tools::ReconcilerTest < ActiveSupport::TestCase
  test "first run materializes a shadow row per definition" do
    assert_equal 0, Tool.code_source.count

    assert Tools::Reconciler.run!

    session_names = Tools::Registry.for_audience(:session).map(&:name)
    assert_equal session_names.sort, Tool.code_source.not_deleted.pluck(:name).sort
    chat = Tool.code_source.find_by!(name: "chat_post_message")
    assert_equal "app", chat.execution_mode.to_s
    assert_equal "chat", chat.requires_integration
    assert_equal %w[messaging chat], chat.tags
    assert chat.enabled?
    lifecycle = Tool.code_source.find_by!(name: "finish_session")
    assert_not lifecycle.user_attachable
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

  test "resurrects a retired row, enabled, when its definition returns" do
    Tools::Reconciler.run!
    row = Tool.code_source.find_by!(name: "board_get_task")
    row.update_columns(deleted_at: Time.current, enabled: false)

    Tools::Reconciler.run!

    row.reload
    assert_nil row.deleted_at
    assert row.enabled?
  end

  test "materializing on demand never retires a row this code does not define" do
    Tools::Reconciler.run!
    renamed = Tool.code_source.find_by!(name: "board_get_task")
    renamed.update_columns(name: "board_get_task_from_a_newer_release")

    rows = Tool.shadow_rows_for_names([ "board_get_task" ])

    assert_equal [ "board_get_task" ], rows.map(&:name)
    renamed.reload
    assert_nil renamed.deleted_at
    assert renamed.enabled?
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
