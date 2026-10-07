# frozen_string_literal: true

require "test_helper"

# Approving, by its code, a pairing the Aixle Flow app started in YouTrack.
class Web::Integrations::YoutrackConnectTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user, name: "Support")
    @pairing, = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud")
  end

  test "signing in comes first" do
    get youtrack_connect_path

    assert_redirected_to login_path
  end

  test "the page offers the projects the user can connect integrations in" do
    sign_in_as(@user)

    get youtrack_connect_path

    assert_inertia_page "Integrations/YoutrackConnect"
    assert_inertia_props { |props| assert_equal [ "Support" ], props[:projects].pluck(:name) }
  end

  test "the code someone typed approves the pairing for the chosen project" do
    sign_in_as(@user)

    post youtrack_connect_path, params: { code: @pairing.code.downcase, project_id: @project.id }

    assert_redirected_to youtrack_connect_path
    assert_match(/Go back to YouTrack/, flash[:notice])
    assert_equal [ "approved", @project, @user ], @pairing.reload.then { |p| [ p.state, p.project, p.user ] }
  end

  test "an unknown code or a project the user cannot connect in approves nothing" do
    sign_in_as(@user)
    stranger = create(:company)
    other = create(:project, company: stranger, owner: create(:user, company: stranger))

    post youtrack_connect_path, params: { code: "ZZZZ-ZZZZ", project_id: @project.id }
    assert_match(/unknown or has expired/, flash[:alert])

    post youtrack_connect_path, params: { code: @pairing.code, project_id: other.id }
    assert_match(/Choose a project/, flash[:alert])

    assert_equal "pending", @pairing.reload.state
  end
end
