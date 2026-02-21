# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      class TerminalSessionsControllerTest < ActionController::TestCase
        setup do
          @user = create(:user, :with_company)
          @company = @user.company
          sign_in(@user)
        end

        def json
          JSON.parse(response.body)
        end

        # INDEX — company-wide
        test "#index returns all company sessions" do
          my_session = create(:terminal_session, :auth_setup, user: @user, agent_type: "claude_code")

          teammate = create(:user, company: @company)
          teammate_session = create(:terminal_session, :auth_setup, user: teammate, agent_type: "codex")

          outsider = create(:user, :with_company)
          outsider_session = create(:terminal_session, :auth_setup, user: outsider, agent_type: "codex")

          get :index
          assert_response :success

          ids = json["items"].pluck("id")
          assert_includes ids, my_session.id
          assert_includes ids, teammate_session.id
          assert_not_includes ids, outsider_session.id
        end

        test "#index orders by created_at desc with pagination" do
          old_session = create(:terminal_session, :auth_setup, user: @user, created_at: 2.days.ago)
          new_session = create(:terminal_session, :auth_setup, user: @user, created_at: 1.hour.ago)

          get :index
          assert_response :success

          ids = json["items"].pluck("id")
          assert_equal [ new_session.id, old_session.id ], ids

          meta = json["meta"]
          assert_equal 1, meta["page"]
          assert meta["total_count"] >= 2
        end

        test "#index filters by agent_type via ransack" do
          claude = create(:terminal_session, :auth_setup, user: @user, agent_type: "claude_code")
          codex = create(:terminal_session, :auth_setup, user: @user, agent_type: "codex")

          get :index, params: { q: { agent_type_eq: "claude_code" } }
          assert_response :success

          ids = json["items"].pluck("id")
          assert_includes ids, claude.id
          assert_not_includes ids, codex.id
        end

        test "#index filters by state via ransack" do
          running = create(:terminal_session, user: @user, state: "running")
          finished = create(:terminal_session, :collected, user: @user)

          get :index, params: { q: { state_eq: "finished" } }
          assert_response :success

          ids = json["items"].pluck("id")
          assert_includes ids, finished.id
          assert_not_includes ids, running.id
        end

        test "#index returns usage and user fields" do
          session = create(:terminal_session, :auth_setup, user: @user, agent_type: "claude_code",
                           total_tokens: 1000, cost_cents: 5, models: [ "claude-4" ])

          get :index
          assert_response :success

          item = json["items"].find { |s| s["id"] == session.id }
          assert_equal 1000, item["total_tokens"]
          assert_equal 5, item["cost_cents"]
          assert_equal [ "claude-4" ], item["models"]
          assert_equal @user.name, item["user_name"]
        end

        # SHOW
        test "#show returns session from company" do
          teammate = create(:user, company: @company)
          session = create(:terminal_session, :running, user: teammate, agent_type: "codex")

          get :show, params: { id: session.id }
          assert_response :success

          assert_equal session.id, json["data"]["id"]
        end

        test "#show returns 404 for session from another company" do
          outsider = create(:user, :with_company)
          session = create(:terminal_session, :auth_setup, user: outsider)

          get :show, params: { id: session.id }
          assert_response :not_found
        end
      end
    end
  end
end
