# frozen_string_literal: true

require "test_helper"

# Authorization matrix for the company-level WorkflowCatalog controller, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::WorkflowCatalogPolicy, context = BaseContext, no project):
#   index?     => company_member?                 (read)
#   duplicate? => company_member? && !read_only?  (write)
#
# This is the "any company member" case: EVERY persona — including a
# foreign-company admin — may read the catalog, and every one but the viewer may
# copy from it (a copy creates a workflow and its resources in the project). The controller (not the policy) keeps users inside their own
# company's data via record scoping: `Workflow.published_in_company(current_company)`
# and `Project.for_user(current_user)`. So the matrix here asserts that no company
# member is denied, and each reaches a clean success (a valid workflow + an
# accessible target project) rather than the policy's denial redirect.
class Web::Company::WorkflowCatalogAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  ALL_MEMBERS_READ = {
    owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
    viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :allowed_read
  }.freeze

  WRITERS = {
    owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
    viewer: :denied, stranger: :allowed_write, foreign_admin: :allowed_write
  }.freeze

  setup do
    setup_company_authz_personas

    # A project every in-company persona can reach (owner via ownership, admin via
    # admin?, the rest as collaborators) plus a published workflow living in that
    # project, so duplicate hits the clean success path. Workflows are Project-
    # scoped now, and the catalog surfaces them via Workflow.published_in_company.
    @project = create(:project, company: @company, owner: @owner)
    @workflow = create(:workflow, scope: @project, published_at: Time.current)
    [ @collaborator, @viewer, @stranger ].each { |u| @project.add_collaborator(u) }

    # The foreign admin is authorized too (company_id present), but is scoped to
    # their OWN company's records — give them a project in their company plus a
    # published workflow in it so their allowed request also lands on the success path.
    @foreign_project = create(:project, company: @foreign_company, owner: @foreign_admin)
    @foreign_workflow = create(:workflow, scope: @foreign_project, published_at: Time.current)
  end

  teardown { teardown_authz }

  test "index: any authenticated company member can read the catalog" do
    assert_role_matrix(ALL_MEMBERS_READ, transport: :web) do
      get company_workflow_catalog_index_path
    end
  end

  # Each persona targets a workflow + project it can reach, so the allowed outcome
  # is the duplicator's success redirect (302, no denial alert) — distinguishing a
  # real authorization pass from the policy's denial redirect.
  test "duplicate: any company member but the viewer may copy a workflow" do
    assert_role_matrix(WRITERS, transport: :web) do |role|
      if role == :foreign_admin
        post duplicate_company_workflow_catalog_path(@foreign_workflow),
             params: { project_id: @foreign_project.id }
      else
        post duplicate_company_workflow_catalog_path(@workflow),
             params: { project_id: @project.id }
      end
    end
  end
end
