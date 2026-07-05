# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Agents controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::AgentsPolicy):
#   index?                       => project_accessible?  (read)
#   create? / update? / destroy? => project_writable?    (write)
# where project_writable? == project_accessible? && !current_user.read_only?
# (read_only? == viewer). Reads: owner/admin/collaborator/viewer allowed;
# strangers and foreign-company users are scoped out (404 — current_project
# `.find` raises RecordNotFound before the policy). Writes: viewer is denied
# (read-only); stranger/foreign => 404. Agents are polymorphically scoped to the
# project (Project has_many :agents, as: :scope), so a project-scoped fixture is
# reachable via current_project.agents.find for update/destroy.
class Web::Company::Projects::AgentsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @agent = create(:agent, scope: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_agents_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do
      post company_project_agents_path(@project),
           params: { agent: { name: "agent_#{SecureRandom.hex(4)}", title: "Helper",
                              persona: "You are a helpful assistant." } }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_agent_path(@project, @agent), params: { agent: { title: "Renamed" } }
    end
  end

  # destroy mutates, so build a throwaway agent per role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_agent_path(@project, create(:agent, scope: @project))
    end
  end
end
