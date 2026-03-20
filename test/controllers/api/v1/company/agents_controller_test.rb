# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::AgentsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")

    @agent = @company.agents.create!(
      name: "analyst",
      title: "Business Analyst",
      icon: "📊",
      persona: "Senior analyst with deep expertise in market research.",
      communication_style: "Speaks with precision and clarity.",
      principles: "Ground findings in verifiable evidence."
    )
  end

  # ====== INDEX Tests ======

  test "#index returns company agents for admin" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["name"] == "analyst" }
  end

  test "#index does not return other company agents" do
    @other_company.agents.create!(
      name: "other_agent",
      title: "Other Agent",
      persona: "Other persona"
    )
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    names = json["items"].map { |i| i["name"] }
    refute { names.include?("other_agent") }
  end

  test "#index requires admin role" do
    sign_in @employee

    get :index

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create creates agent" do
    sign_in @admin

    assert_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "pm",
          title: "Product Manager",
          icon: "📋",
          persona: "Product management veteran.",
          communication_style: "Direct and data-sharp.",
          principles: "Ship the smallest thing that validates."
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    agent = Agent.find(json["data"]["id"])
    assert { agent.name == "pm" }
    assert { agent.title == "Product Manager" }
    assert { agent.icon == "📋" }
    assert { agent.scope == @company }
    assert { agent.custom? }
  end

  test "#create auto-downcases name" do
    sign_in @admin

    post :create, params: {
      agent: {
        name: "PM_Agent",
        title: "Product Manager",
        persona: "Product management veteran."
      }
    }

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "pm_agent" }
  end

  test "#create validates name format" do
    sign_in @admin

    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "123invalid", # Must start with letter
          title: "Test",
          persona: "Test persona"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create validates name uniqueness within scope" do
    sign_in @admin

    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "analyst", # Already exists
          title: "Another Analyst",
          persona: "Different persona"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create requires title" do
    sign_in @admin

    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "new_agent",
          persona: "Test persona"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["title"].present? }
  end

  test "#create requires persona" do
    sign_in @admin

    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "new_agent",
          title: "New Agent"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["persona"].present? }
  end

  test "#create requires admin role" do
    sign_in @employee

    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "new_agent",
          title: "New Agent",
          persona: "Test persona"
        }
      }
    end

    assert_response :forbidden
  end

  test "#create requires authentication" do
    assert_no_difference("Agent.count") do
      post :create, params: {
        agent: {
          name: "new_agent",
          title: "New Agent",
          persona: "Test persona"
        }
      }
    end

    assert_response :unauthorized
  end

  # ====== UPDATE Tests ======

  test "#update updates agent fields" do
    sign_in @admin

    patch :update, params: {
      id: @agent.id,
      agent: {
        title: "Senior Business Analyst",
        communication_style: "Updated style"
      }
    }

    assert_response :success
    @agent.reload
    assert { @agent.title == "Senior Business Analyst" }
    assert { @agent.communication_style == "Updated style" }
  end

  test "#update cannot change agent from another company" do
    other_agent = @other_company.agents.create!(
      name: "other_agent",
      title: "Other Agent",
      persona: "Other persona"
    )
    sign_in @admin

    patch :update, params: {
      id: other_agent.id,
      agent: { title: "Hacked" }
    }

    assert_response :not_found
  end

  test "#update requires admin role" do
    sign_in @employee

    patch :update, params: {
      id: @agent.id,
      agent: { title: "Hacked" }
    }

    assert_response :forbidden
  end

  test "#update requires authentication" do
    patch :update, params: {
      id: @agent.id,
      agent: { title: "Hacked" }
    }

    assert_response :unauthorized
  end

  # ====== DESTROY Tests ======

  test "#destroy removes agent" do
    sign_in @admin

    assert_difference("Agent.count", -1) do
      delete :destroy, params: { id: @agent.id }
    end

    assert_response :no_content
    assert { Agent.find_by(id: @agent.id).nil? }
  end

  test "#destroy cannot delete agent from another company" do
    other_agent = @other_company.agents.create!(
      name: "other_agent",
      title: "Other Agent",
      persona: "Other persona"
    )
    sign_in @admin

    assert_no_difference("Agent.count") do
      delete :destroy, params: { id: other_agent.id }
    end

    assert_response :not_found
  end

  test "#destroy requires admin role" do
    sign_in @employee

    assert_no_difference("Agent.count") do
      delete :destroy, params: { id: @agent.id }
    end

    assert_response :forbidden
  end

  test "#destroy requires authentication" do
    assert_no_difference("Agent.count") do
      delete :destroy, params: { id: @agent.id }
    end

    assert_response :unauthorized
  end

  # ====== Response Format Tests ======

  test "#create returns expected fields" do
    sign_in @admin

    post :create, params: {
      agent: {
        name: "response_test",
        title: "Response Test Agent",
        icon: "🧪",
        persona: "Test persona content",
        communication_style: "Test style",
        principles: "Test principles"
      }
    }

    assert_response :created
    json = response.parsed_body
    data = json["data"]
    assert { data["id"].present? }
    assert { data["name"] == "response_test" }
    assert { data["title"] == "Response Test Agent" }
    assert { data["icon"] == "🧪" }
    assert { data["persona"] == "Test persona content" }
    assert { data["communication_style"] == "Test style" }
    assert { data["principles"] == "Test principles" }
    assert { data["source"] == "custom" }
    assert { data["scope_type"] == "Company" }
    assert { data["scope_id"] == @company.id }
    assert { data["scope_indicator"] == "company" }
    assert { data["created_at"].present? }
    assert { data["updated_at"].present? }
  end
end
