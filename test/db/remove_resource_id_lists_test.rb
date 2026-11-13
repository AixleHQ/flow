# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261113120000_remove_resource_id_lists")

class RemoveResourceIdListsTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @workflow = create(:workflow, scope: @project)
  end

  teardown { Step.reset_column_information }

  test "rolled back, it fills the lists again from the links, in order; run again, it takes them out" do
    first, second = create_list(:repository, 2, scope: @project)
    tool = create(:tool, scope: @project)
    step = create(:step, workflow: @workflow, repository_ids: [ second.id, first.id ])
    @workflow.merge_config!("base_tool_ids" => [ tool.id ], "inherit_all_project_resources" => true)

    migrate(:down)

    assert_equal [ second.id, first.id ], json("SELECT repository_ids FROM steps WHERE id = #{step.id}")
    assert_empty json("SELECT tool_ids FROM steps WHERE id = #{step.id}")
    assert_equal({ "base_tool_ids" => [ tool.id ], "inherit_all_project_resources" => true }, stored_config)

    migrate(:up)

    assert_not_includes ActiveRecord::Base.connection.columns(:steps).map(&:name), "repository_ids"
    assert_equal({ "inherit_all_project_resources" => true }, stored_config)
  end

  private

  def migrate(direction)
    migration = RemoveResourceIdLists.new
    migration.suppress_messages { migration.migrate(direction) }
  end

  def json(sql) = JSON.parse(ActiveRecord::Base.connection.select_value(sql))

  def stored_config = json("SELECT config FROM workflows WHERE id = #{@workflow.id}")
end
