# frozen_string_literal: true

require "test_helper"

class Web::ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "show renders profile page" do
    get profile_path
    assert_inertia_page "Profile/Show"
  end

  test "update redirects on success" do
    patch profile_path, params: { profile: { name: "Updated Name" } }
    assert_response :redirect
  end

  # Regression: the profile form edits the name (User) AND the agent language,
  # which is a per-company onboarding answer on the MEMBERSHIP. Permitting only
  # :name in profile_params made language changes silently no-op.
  test "update saves the agent language onto the CURRENT membership" do
    patch profile_path, params: { profile: { name: "Updated Name", preferred_agent_language: "ru" } }

    assert_response :redirect
    assert_equal "Updated Name", @user.reload.name
    assert_equal "ru", @user.company_memberships.find_by!(company: @company).preferred_agent_language
  end

  # Session sharing is global, not per-membership: it says what this person is
  # willing to let colleagues watch, which does not change with the company they
  # happen to be acting for.
  test "update saves the session visibility preferences onto the user" do
    patch profile_path, params: { profile: { name: @user.name,
                                             share_active_sessions: "1",
                                             share_completed_sessions: "0" } }

    assert_response :redirect
    @user.reload
    assert @user.share_active_sessions
    assert_equal false, @user.share_completed_sessions # rubocop:disable Minitest/RefuteFalse
  end

  test "update leaves the OTHER company's language alone" do
    other = create(:company)
    other_membership = create(:company_membership, user: @user, company: other,
                                                   preferred_agent_language: "en")

    patch profile_path, params: { profile: { preferred_agent_language: "ru" } }

    assert_equal "ru", @user.company_memberships.find_by!(company: @company).preferred_agent_language
    assert_equal "en", other_membership.reload.preferred_agent_language
  end

  # The usage panel reads Anthropic over HTTP. Deferring it is the contract that
  # keeps a slow or throttled vendor off the profile page's critical path.
  test "show defers the usage limits prop rather than blocking the render on the vendor" do
    get profile_path

    assert_inertia_deferred_props :usage_limits, group: "limits"
    assert_inertia_props do |props|
      !props.key?(:usageLimits)
    end
  end

  test "the deferred usage limits prop resolves to an empty list when no credential bills against a plan" do
    # Billed to the member's own AWS account, so there is no plan window to read
    # — and no request to Anthropic to find that out.
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code",
                              config_data: { "awsBedrock" => { "region" => "us-east-1" } })

    get profile_path
    inertia_load_deferred_props("limits")

    assert_inertia_props usageLimits: []
  end

  test "update_default_model redirects on success" do
    credential = create(:agent_credential, user: @user)

    put update_default_model_profile_path, params: {
      agent_credential_id: credential.id,
      default_model: "claude-sonnet-4-20250514"
    }

    assert_response :redirect
  end

  test "destroy_credential redirects on success" do
    credential = create(:agent_credential, user: @user)

    delete destroy_credential_profile_path, params: {
      agent_credential_id: credential.id
    }

    assert_response :redirect
  end

  # The page only renders the CURRENT company's credentials, and these two actions take
  # an id — so an id from another company must not resolve. Editing or deleting it here
  # would reach across a tenant boundary into a separately-billed agent account.
  test "update_default_model refuses a credential from another company" do
    credential = other_company_credential

    put update_default_model_profile_path, params: {
      agent_credential_id: credential.id,
      default_model: "claude-sonnet-4-20250514"
    }

    assert_response :not_found
    assert_nil credential.reload.metadata["default_model"]
  end

  test "destroy_credential refuses a credential from another company" do
    credential = other_company_credential

    delete destroy_credential_profile_path, params: { agent_credential_id: credential.id }

    assert_response :not_found
    assert AgentCredential.exists?(credential.id)
  end

  private

  # The same person's credential in a second company they belong to: theirs, but not
  # this page's to touch.
  def other_company_credential
    other = create(:company)
    create(:company_membership, user: @user, company: other)
    create(:agent_credential, user: @user, company: other, agent_type: "codex", metadata: {})
  end
end
