# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class TerminalSessionsControllerTest < ActionController::TestCase
          setup do
            @user = create(:user, :with_company)
            @company = @user.company
            @project = create(:project, company: @company, owner: @user)
            sign_in(@user)
          end

          def json
            JSON.parse(response.body)
          end

          # INDEX — project-scoped
          test "#index returns only sessions for the project" do
            project_session = create(:terminal_session, :auth_setup, user: @user, project: @project)
            other_session = create(:terminal_session, :auth_setup, user: @user, project: nil)

            other_project = create(:project, company: @company, owner: @user)
            other_project_session = create(:terminal_session, :auth_setup, user: @user, project: other_project)

            get :index, params: { project_id: @project.id }
            assert_response :success

            ids = json["items"].pluck("id")
            assert_includes ids, project_session.id
            assert_not_includes ids, other_session.id
            assert_not_includes ids, other_project_session.id
          end

          test "#index filters by agent_type" do
            claude = create(:terminal_session, :auth_setup, user: @user, project: @project, agent_type: "claude_code")
            codex = create(:terminal_session, :auth_setup, user: @user, project: @project, agent_type: "codex")

            get :index, params: { project_id: @project.id, q: { agent_type_eq: "codex" } }
            assert_response :success

            ids = json["items"].pluck("id")
            assert_includes ids, codex.id
            assert_not_includes ids, claude.id
          end

          test "#index includes teammate sessions on same project" do
            teammate = create(:user, company: @company)
            create(:project_collaborator, project: @project, user: teammate)
            teammate_session = create(:terminal_session, :auth_setup, user: teammate, project: @project)

            get :index, params: { project_id: @project.id }
            assert_response :success

            ids = json["items"].pluck("id")
            assert_includes ids, teammate_session.id
          end

          # SHOW
          test "#show returns project session" do
            session = create(:terminal_session, :running, user: @user, project: @project)

            get :show, params: { project_id: @project.id, id: session.id }
            assert_response :success

            assert_equal session.id, json["data"]["id"]
          end
        end
      end
    end
  end
end
