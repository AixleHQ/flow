# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Statistic::TopAgentsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)
  end

  # ====== SHOW Tests ======

  test "#show returns 200 for company admin" do
    sign_in @admin

    get :show

    assert_response :success
  end

  test "#show returns 200 for company employee" do
    sign_in @employee

    get :show

    assert_response :success
  end

  test "#show requires authentication" do
    get :show

    assert_response :unauthorized
  end

  test "#show returns a hash with top_agents array" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json.is_a?(Hash) }
    assert { json["top_agents"].is_a?(Array) }
  end

  test "#show returns agents ranked by session count" do
    agent_a = Agent.create!(name: "agent_a", title: "Agent A", persona: "Persona A", scope: @company)
    agent_b = Agent.create!(name: "agent_b", title: "Agent B", persona: "Persona B", scope: @company)

    3.times { create(:terminal_session, user: @admin, configured_agent: agent_a) }
    1.times { create(:terminal_session, user: @admin, configured_agent: agent_b) }

    sign_in @admin

    get :show

    assert_response :success
    items = response.parsed_body["top_agents"]
    assert { items.length == 2 }
    assert { items.first["name"] == "agent_a" }
    assert { items.first["sessions_count"] == 3 }
    assert { items.second["name"] == "agent_b" }
    assert { items.second["sessions_count"] == 1 }
  end

  test "#show includes rank, name, agent_type, sessions_count, total_cost_cents" do
    agent = Agent.create!(name: "my_agent", title: "My Agent", persona: "Persona", scope: @company)
    create(:terminal_session, user: @admin, configured_agent: agent, cost_cents: 500)

    sign_in @admin

    get :show

    assert_response :success
    entry = response.parsed_body["top_agents"].first
    assert { entry.key?("rank") }
    assert { entry.key?("name") }
    assert { entry.key?("agent_type") }
    assert { entry.key?("sessions_count") }
    assert { entry.key?("total_cost_cents") }
    assert { entry["rank"] == 1 }
    assert { entry["name"] == "my_agent" }
    assert { entry["total_cost_cents"] == 500 }
  end

  test "#show excludes agents from other companies" do
    other_project = create(:project, company: @other_company, owner: @other_admin)
    other_agent = Agent.create!(name: "other_agent", title: "Other Agent", persona: "P", scope: @other_company)
    create(:terminal_session, user: @other_admin, project: other_project, configured_agent: other_agent)

    sign_in @admin

    get :show

    assert_response :success
    assert { response.parsed_body["top_agents"].empty? }
  end

  test "#show respects limit parameter" do
    5.times do |i|
      agent = Agent.create!(name: "agent_#{i}", title: "Agent #{i}", persona: "P#{i}", scope: @company)
      (5 - i).times { create(:terminal_session, user: @admin, configured_agent: agent) }
    end

    sign_in @admin

    get :show, params: { limit: 3 }

    assert_response :success
    assert { response.parsed_body["top_agents"].length == 3 }
  end
end
