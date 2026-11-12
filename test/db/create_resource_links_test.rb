# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261112100000_create_resource_links")

class CreateResourceLinksTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow)
  end

  def remigrate
    migration = CreateResourceLinks.new
    migration.suppress_messages do
      migration.down
      migration.up
    end
  end

  test "carries a step's lists over in their order, without the ids whose rows are gone" do
    first, second = create_list(:repository, 2, scope: @project)
    server = create(:mcp_server, scope: @project)
    gone = create(:repository, scope: @project).tap(&:destroy!).id
    @step.update_columns(repository_ids: [ second.id, gone, first.id, second.id ], mcp_server_ids: [ server.id.to_s ])

    remigrate

    links = StepResourceLink.where(step: @step).order(:position)
    assert_equal [ second.id, first.id ], links.where.not(repository_id: nil).pluck(:repository_id)
    assert_equal [ server.id ], links.where.not(mcp_server_id: nil).pluck(:mcp_server_id)
  end

  test "carries a workflow's base lists over and ignores the rest of its config" do
    repository = create(:repository, scope: @project)
    item = create(:config_item, scope: @project)
    gone = create(:repository, scope: @project).tap(&:destroy!).id
    @workflow.update_columns(config: { "base_repository_ids" => [ gone, repository.id ],
                                       "base_config_item_ids" => [ item.id ],
                                       "inherit_all_project_resources" => true })

    remigrate

    links = WorkflowResourceLink.where(workflow: @workflow)
    assert_equal [ repository.id ], links.where.not(repository_id: nil).pluck(:repository_id)
    assert_equal [ item.id ], links.where.not(config_item_id: nil).pluck(:config_item_id)
    assert_equal 2, links.count
  end

  test "a list that is not an array is skipped rather than failing the migration" do
    @workflow.update_columns(config: { "base_tool_ids" => "1,2" })

    remigrate

    assert_empty WorkflowResourceLink.where(workflow: @workflow)
  end
end
