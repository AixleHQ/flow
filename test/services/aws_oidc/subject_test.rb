# frozen_string_literal: true

require "test_helper"

module AwsOidc
  class SubjectTest < ActiveSupport::TestCase
    setup do
      company = create(:company)
      @project = create(:project, company: company, owner: create(:user, company: company))
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow)
    end

    test "a workflow step is named by its workflow and step ids" do
      assert_equal "workflow:#{@workflow.id}:step:#{@step.id}", Subject.for_step(@step)
    end

    test "a draft's step is named by the source workflow and the step it was copied from, behind draft:" do
      draft = create(:workflow, scope: @project, name: "#{@workflow.name} (draft)", draft_of: @workflow)
      copy = create(:step, workflow: draft, origin_step: @step)

      assert_equal "draft:workflow:#{@workflow.id}:step:#{@step.id}", Subject.for_step(copy)
    end

    test "a step added in a draft has no source step and says so" do
      draft = create(:workflow, scope: @project, name: "#{@workflow.name} (draft)", draft_of: @workflow)
      added = create(:step, workflow: draft)

      assert_equal "draft:workflow:#{@workflow.id}:step:new-#{added.id}", Subject.for_step(added)
    end

    test "verify has its own subject per integration" do
      integration = create(:integration, :aws_oidc)

      assert_equal "verify:integration:#{integration.id}", Subject.for_verify(integration)
    end
  end
end
