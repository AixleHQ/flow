# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the entity versions API (docs/testing.md §2).
#
# Policy (Api::V1::Projects::EntityVersionsPolicy):
#   index?, show?       => project_accessible?  (read)
#   revert?, restore?   => project_writable?    (write)
class Api::V1::Projects::EntityVersionsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @agent = create(:agent, scope: @project, title: "First")
    Versions.save!(@agent, actor: Versions::Actor.ui(@owner)) { @agent.update!(title: "Second") }
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) do
      get api_v1_project_entity_versions_path(@project, versionable_type: "Agent", versionable_id: @agent.id)
    end
  end

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_entity_version_path(@project, @agent.latest_version) }
  end

  test "revert is a project write" do
    assert_project_write(transport: :api) do
      post revert_api_v1_project_entity_version_path(@project, @agent.entity_versions.find_by(number: 1)), as: :json
    end
  end

  test "restore is a project write" do
    assert_project_write(transport: :api) do
      agent = create(:agent, scope: @project)
      Versions.archive!(agent, actor: Versions::Actor.ui(@owner))
      post restore_api_v1_project_entity_versions_path(@project),
           params: { versionable_type: "Agent", versionable_id: agent.id }, as: :json
    end
  end
end
