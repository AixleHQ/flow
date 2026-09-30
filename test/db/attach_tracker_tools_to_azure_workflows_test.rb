# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260930150200_attach_tracker_tools_to_azure_workflows")

class AttachTrackerToolsToAzureWorkflowsTest < ActiveSupport::TestCase
  setup do
    @migration = AttachTrackerToolsToAzureWorkflows.new
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
  end

  def migrate
    @migration.suppress_messages { @migration.up }
  end

  def tracker_tool_ids
    Tool.where(source: "code", name: AttachTrackerToolsToAzureWorkflows::TRACKER_TOOLS).pluck(:id)
  end

  test "a workflow of a project with an Azure connection gets the tracker tools, keeping what it had" do
    kept = Tool.shadow_for(Tools::Registry.fetch("board_list_tasks"))
    workflow = create(:workflow, scope: @project, config: { "base_tool_ids" => [ kept.id ] })

    migrate

    base = workflow.reload.base_tool_ids.map(&:to_i)
    assert_includes base, kept.id
    assert_equal tracker_tool_ids.sort, (base - [ kept.id ]).sort
    assert_equal 11, tracker_tool_ids.size
  end

  test "running it twice attaches nothing twice, and other projects are left alone" do
    owner = create(:user, company: @project.company)
    elsewhere = create(:workflow, scope: create(:project, company: @project.company, owner: owner))
    workflow = create(:workflow, scope: @project)

    migrate
    migrate

    assert_equal workflow.reload.base_tool_ids.uniq, workflow.base_tool_ids
    assert_empty elsewhere.reload.base_tool_ids
  end
end
