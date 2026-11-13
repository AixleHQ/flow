# frozen_string_literal: true

require "test_helper"

class WorkflowAggregateSaveTest < ActiveSupport::TestCase
  test "a base list an older release left in the config is not saved back over the links" do
    project = create(:project, :standalone)
    linked, stale = create_list(:repository, 2, scope: project)
    workflow = create(:workflow, scope: project, config: { "base_repository_ids" => [ linked.id ] })
    workflow.update_column(:config, { "base_repository_ids" => [ stale.id ] })

    WorkflowAggregateSave.new(workflow.reload, { "config" => { "inherit_all_project_resources" => true }, "steps" => [] }).apply!

    assert_equal [ linked.id ], workflow.reload.base_repository_ids
    assert_equal({ "inherit_all_project_resources" => true }, workflow.config)
  end
end
