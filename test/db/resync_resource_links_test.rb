# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261113100000_resync_resource_links")

class ResyncResourceLinksTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @workflow = create(:workflow, scope: @project)
  end

  def resync
    migration = ResyncResourceLinks.new
    migration.suppress_messages { migration.up }
  end

  test "links again, in its order, a list written without mirroring" do
    first, second = create_list(:repository, 2, scope: @project)
    step = create(:step, workflow: @workflow, repository_ids: [ first.id ])
    step.update_column(:repository_ids, [ second.id, first.id ])

    resync

    assert_equal [ second.id, first.id ], linked(StepResourceLink.where(step: step), :repository_id)
  end

  test "drops the links of a list emptied without mirroring" do
    tool = create(:tool, scope: @project)
    @workflow.merge_config!("base_tool_ids" => [ tool.id ])
    @workflow.update_column(:config, {})

    resync

    assert_empty WorkflowResourceLink.where(workflow: @workflow)
  end

  test "keeps the rows of a list its links agree with, a deleted resource aside" do
    kept, deleted = create_list(:repository, 2, scope: @project)
    step = create(:step, workflow: @workflow, repository_ids: [ deleted.id, kept.id ])
    deleted.destroy!
    rows = StepResourceLink.where(step: step).pluck(:id)

    resync

    assert_equal rows, StepResourceLink.where(step: step).pluck(:id)
  end

  private

  def linked(links, column)
    links.where.not(column => nil).order(:position).pluck(column)
  end
end
