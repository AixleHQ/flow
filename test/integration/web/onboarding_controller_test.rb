# frozen_string_literal: true

require "test_helper"

class Web::OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(
      :user,
      company: @company,
      onboarding_state: "step1",
      password: AuthHelper::TEST_PASSWORD,
      password_confirmation: AuthHelper::TEST_PASSWORD
    )
    sign_in_as(@user)
  end

  test "show renders onboarding when not completed" do
    get onboarding_path
    assert_inertia_page "Onboarding/OnboardingPage"
  end

  test "update redirects on success" do
    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en" }
    }
    assert_response :redirect
  end

  test "go_next advances from step1 to step2" do
    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en", onboarding_state_event: "go_next" }
    }
    assert_equal "step2", @user.company_memberships.sole.reload.onboarding_state
  end

  test "viewer completes onboarding without agents" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step2",
                                    position: "dev", preferred_agent_language: "en",
                                    email: "client2@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", viewer.company_memberships.sole.reload.onboarding_state
  end

  test "viewer workflow preview loads workflows in one query whatever the project count" do
    sign_in_as(create_viewer)
    workflows = Array.new(3) { create(:workflow, scope: create(:project, company: @company, owner: @user)) }

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql]
    end

    begin
      get onboarding_path
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_inertia_page "Onboarding/OnboardingPage"
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "workflows"/) }, queries.grep(/FROM "workflows"/).inspect
    assert_inertia_props { |props| assert_equal workflows.first.name, props[:viewerWorkflowPreview][:workflowName] }
  end

  test "viewer workflow preview skips archived workflows" do
    sign_in_as(create_viewer)
    project = create(:project, company: @company, owner: @user)
    create(:workflow, scope: project, deleted_at: Time.current)
    live = create(:workflow, scope: project)

    get onboarding_path

    assert_inertia_props { |props| assert_equal live.name, props[:viewerWorkflowPreview][:workflowName] }
  end

  test "viewer workflow preview is nil when every workflow is archived" do
    sign_in_as(create_viewer)
    create(:workflow, scope: create(:project, company: @company, owner: @user), deleted_at: Time.current)

    get onboarding_path

    assert_inertia_props { |props| assert_nil props[:viewerWorkflowPreview] }
  end

  test "non-viewer cannot complete at step2 without agent credentials (silent no-op)" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "dev", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "step2", membership.reload.onboarding_state
  end

  test "non-viewer completes onboarding at step2 with an agent credential" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "dev", preferred_agent_language: "en")
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", membership.reload.onboarding_state
  end

  private

  def create_viewer
    create(:user, :viewer, company: @company, onboarding_state: "step2",
                           position: "dev", preferred_agent_language: "en",
                           email: "viewer-preview@ext.com",
                           password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
  end
end
