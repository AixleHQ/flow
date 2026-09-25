# frozen_string_literal: true

require "test_helper"

# Policy (Api::V1::Projects::Workflows::AggregatesPolicy): update? => project_writable?
class Api::V1::Projects::Workflows::AggregatesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
  end

  teardown { teardown_authz }

  test "update is a project write" do
    assert_project_write(transport: :api) do
      put api_v1_project_workflow_aggregate_path(@project, @workflow),
          params: { base_version: @workflow.reload.current_version_number, aggregate: { name: @workflow.name, steps: [] } },
          as: :json
    end
  end
end
