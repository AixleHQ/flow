# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261123100001_attach_pull_request_tools_to_workflows")

class AttachPullRequestToolsToWorkflowsTest < ActiveSupport::TestCase
  setup do
    @migration = AttachPullRequestToolsToWorkflows.new
    @integration = create(:integration, :gitlab, :active)
    @project = create(:project, company: @integration.company, owner: create(:user, company: @integration.company))
  end

  def migrate
    @migration.suppress_messages { @migration.up }
  end

  def pull_request_tool_ids
    Tool.where(source: "code", name: AttachPullRequestToolsToWorkflows::PULL_REQUEST_TOOLS).pluck(:id)
  end

  # The migration predates the resource links and works on the jsonb list itself.
  def base_tool_ids(workflow)
    Array(workflow.reload.config["base_tool_ids"])
  end

  test "lists exactly the tools that carry the pull_requests tag" do
    tagged = Tools::Registry.definitions.values.select { |d| d.tags.include?(:pull_requests) }.map(&:name)

    assert_equal tagged.sort, AttachPullRequestToolsToWorkflows::PULL_REQUEST_TOOLS.sort
  end

  test "a workflow of a company with a code-host connection gets the tools, keeping what it had" do
    kept = Tool.shadow_for(Tools::Registry.fetch("board_list_tasks"))
    workflow = create(:workflow, scope: @project)
    workflow.update_columns(config: { "base_tool_ids" => [ kept.id ] })

    migrate

    base = base_tool_ids(workflow).map(&:to_i)
    assert_includes base, kept.id
    assert_equal pull_request_tool_ids.sort, (base - [ kept.id ]).sort
    assert_equal 10, pull_request_tool_ids.size
  end

  test "running it twice attaches nothing twice, and companies without a connection are left alone" do
    other_company = create(:company)
    other_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    elsewhere = create(:workflow, scope: other_project)
    workflow = create(:workflow, scope: @project)

    migrate
    migrate

    assert_equal base_tool_ids(workflow).uniq, base_tool_ids(workflow)
    assert_empty base_tool_ids(elsewhere)
  end

  test "a project-level connection reaches only that project's workflows" do
    company = create(:company)
    owner = create(:user, company: company)
    connected = create(:project, company: company, owner: owner)
    other = create(:project, company: company, owner: owner)
    create(:integration, :gitlab, :active, company: company, project: connected)
    on_connected = create(:workflow, scope: connected)
    on_other = create(:workflow, scope: other)

    migrate

    assert_not_empty base_tool_ids(on_connected)
    assert_empty base_tool_ids(on_other)
  end
end
