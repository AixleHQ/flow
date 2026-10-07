# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::TriggersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "the page gets the project's live workflows, board columns and trackers for the form's pickers" do
    column = create(:board_column, board: create(:board, project: @project), name: "Inbox", position: 1)
    intake = create(:workflow, scope: @project, name: "Intake")
    ColumnWorkflowBinding.create!(board_column: column, workflow: intake, created_by: @user)
    archived = create(:workflow, scope: @project, name: "Old")
    archived.update_columns(deleted_at: Time.current)

    get company_project_triggers_path(@project)

    assert_inertia_page "Projects/Triggers/TriggersPage"
    assert_inertia_props do |props|
      props[:workflows].map { |w| w["name"] } == [ "Intake" ] &&
        props[:boardColumns].map { |c| c["boundWorkflowName"] } == [ "Intake" ] &&
        props[:trackers] == []
    end
  end

  test "the chat form offers the connected messengers and the conversations the Teams bot knows" do
    create(:integration, provider: :slack, status: :active, company: @company, project: nil)
    teams = create(:integration, provider: :teams, status: :active, company: @company, project: nil)
    create(:integration, provider: :teams, status: :active, company: create(:company), project: nil)
    teams.chat_conversations.create!(provider: "teams", external_id: "19:a@thread.tacv2", kind: "channel",
                                     name: "Onboarding", team_name: "Sales")
    teams.chat_conversations.create!(provider: "teams", external_id: "a:1dm", kind: "direct")

    get company_project_triggers_path(@project)

    assert_inertia_props do |props|
      props[:chatProviders].map { |p| p[:key] } == %w[slack teams] &&
        props[:chatProviders].last[:conversations] ==
          [ { "id" => "19:a@thread.tacv2", "name" => "Onboarding", "kind" => "channel", "teamName" => "Sales" } ]
    end
  end
end
