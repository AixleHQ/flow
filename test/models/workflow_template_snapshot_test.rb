# frozen_string_literal: true

require "test_helper"

class WorkflowTemplateSnapshotTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @workflow = create(:workflow, scope: @company, kind: "template_snapshot")
  end

  test "template snapshot cannot be updated" do
    @workflow.name = "Changed"
    assert_not @workflow.valid?
    assert_includes @workflow.errors[:base], "Template snapshots cannot be modified"
  end
end
