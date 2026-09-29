# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::OwnershipsControllerTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "only the owner and a company admin may transfer" do
    expectations = {
      owner: :allowed_write, admin: :allowed_write, collaborator: :denied,
      viewer: :denied, stranger: :not_found, foreign_admin: :not_found
    }

    assert_role_matrix(expectations, transport: :web) do
      target = create(:user, :employee, :onboarding_completed, company: @company)
      patch company_project_ownership_path(@project), params: { ownership: { user_id: target.id } }
    end
  end

  test "the owner hands the project over and stays on as a collaborator" do
    sign_in_as(@owner)

    patch company_project_ownership_path(@project), params: { ownership: { user_id: @collaborator.id } },
                                                    headers: { "HTTP_REFERER" => company_project_members_url(@project) }

    assert_redirected_to company_project_members_url(@project)
    assert_equal "Ownership transferred to #{@collaborator.name}.", flash[:notice]
    @project.reload
    assert_equal @collaborator, @project.owner
    assert_equal [ @owner, @viewer ].sort_by(&:id), @project.collaborators.order(:id).to_a
  end

  test "a viewer or another company's user is refused as the new owner" do
    sign_in_as(@admin)

    [ @viewer, @foreign_admin ].each do |target|
      patch company_project_ownership_path(@project), params: { ownership: { user_id: target.id } }

      assert_response :redirect
      assert_predicate session["inertia_errors"][:owner], :present?
    end
    assert_equal @owner, @project.reload.owner
  end

  test "settings offers the transfer with eligible candidates only to those who may transfer" do
    sign_in_as(@owner)
    get company_project_settings_path(@project)

    ownership = inertia.props[:ownership]
    assert ownership[:canTransfer]
    candidate_ids = ownership[:candidates].pluck(:id)
    assert_includes candidate_ids, @collaborator.id
    assert_includes candidate_ids, @admin.id
    assert_not_includes candidate_ids, @viewer.id
    assert_not_includes candidate_ids, @owner.id
    assert_not_includes candidate_ids, @foreign_admin.id
    assert(ownership[:candidates].find { |c| c[:id] == @collaborator.id }[:collaborator])

    sign_in_as(@collaborator)
    get company_project_members_path(@project)

    assert_equal({ canTransfer: false, candidates: [] }, inertia.props[:ownership].to_h.symbolize_keys)
  end
end
