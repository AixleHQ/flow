# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::SkillsController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::SkillsPolicy, project-scoped ProjectContext):
#   index?   => project_accessible?  (read)
#   create?  => project_writable?    (write; read-only viewer denied)
#   manual?  => project_writable?    (write; read-only viewer denied)
#   destroy? => project_writable?    (write; read-only viewer denied)
# Inaccessible project (stranger / foreign admin) => 404: current_project is
# `Project.for_user(current_user).find(...)`, whose scoped `.find` raises
# RecordNotFound before the policy runs (rescued to 404 by show_exceptions).
#
# create sends an empty body on purpose: SkillsRegistryService.install raises
# RegistryError "skill_id is required" BEFORE any skills.sh HTTP/CLI call, so an
# allowed role gets a deterministic, vendor-free 302 redirect (no stubbing, R2) —
# the redirect proves authorization passed. destroy deletes a throwaway
# project-scoped skill per role, a clean vendor-free write (302 + notice).
class Web::Company::Projects::SkillsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_skills_path(@project) }
  end

  # Allowed roles reach the action and hit the deterministic "skill_id is
  # required" guard (rescued to a 302 redirect); the viewer is denied and
  # non-members are scoped out to 404.
  test "create is a project write (allowed roles reach a vendor-free redirect guard)" do
    assert_project_write(allowed: :redirect) { post company_project_skills_path(@project) }
  end

  # manual authoring carries the same authority as installing: both put
  # instructions into every session the project runs. An empty body fails
  # SKILL.md validation before anything is written, so an allowed role gets a
  # deterministic vendor-free 302 and the viewer is still denied.
  test "manual is a project write (allowed roles reach the validation guard)" do
    assert_project_write(allowed: :redirect) { post manual_company_project_skills_path(@project) }
  end

  # destroy mutates, so build a throwaway project-scoped skill per role iteration;
  # an allowed role deletes it cleanly (302 + notice, no alert).
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_skill_path(@project, create(:skill, scope: @project))
    end
  end
end
