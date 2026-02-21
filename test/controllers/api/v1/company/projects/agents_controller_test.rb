# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::AgentsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    # Company-level agent
    @company_agent = @company.agents.create!(
      name: "analyst",
      title: "Business Analyst",
      icon: "📊",
      persona: "Company-level analyst persona."
    )

    # Project-level agent
    @project_agent = @project.agents.create!(
      name: "pm",
      title: "Product Manager",
      icon: "📋",
      persona: "Project-level PM persona."
    )
  end

  # ====== INDEX Tests (Merged List) ======

  test "#index returns merged list of company and project agents" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 2 }

    names = json["items"].map { |i| i["name"] }
    assert { names.include?("analyst") }
    assert { names.include?("pm") }
  end

  test "#index shows correct scope_indicator" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body

    company_item = json["items"].find { |i| i["name"] == "analyst" }
    assert { company_item["scope_indicator"] == "company" }

    project_item = json["items"].find { |i| i["name"] == "pm" }
    assert { project_item["scope_indicator"] == "project" }
  end

  test "#index shows overrides_company for overriding agents" do
    # Create project-level agent with same name as company agent
    @project.agents.create!(
      name: "analyst",
      title: "Project Analyst",
      persona: "Project-specific analyst persona."
    )
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body

    analyst = json["items"].find { |i| i["name"] == "analyst" }
    assert { analyst["scope_indicator"] == "overrides_company" }
    assert { analyst["title"] == "Project Analyst" } # Project version
  end

  test "#index accessible by project collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id }

    assert_response :success
  end

  test "#index not accessible by non-member" do
    sign_in @other_user

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index, params: { project_id: @project.id }

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create creates project-level agent" do
    sign_in @owner

    assert_difference("Agent.count") do
      post :create, params: {
        project_id: @project.id,
        agent: {
          name: "architect",
          title: "Solution Architect",
          persona: "Technical architecture expert."
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    agent = Agent.find(json["data"]["id"])
    assert { agent.scope == @project }
    assert { agent.scope_type == "Project" }
  end

  test "#create allows same name as company agent (override)" do
    sign_in @owner

    assert_difference("Agent.count") do
      post :create, params: {
        project_id: @project.id,
        agent: {
          name: "analyst", # Same as company agent
          title: "Project-specific Analyst",
          persona: "Custom analyst for this project."
        }
      }
    end

    assert_response :created
  end

  test "#create accessible by project collaborator" do
    sign_in @collaborator

    assert_difference("Agent.count") do
      post :create, params: {
        project_id: @project.id,
        agent: {
          name: "new_agent",
          title: "New Agent",
          persona: "New persona."
        }
      }
    end

    assert_response :created
  end

  test "#create not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("Agent.count") do
      post :create, params: {
        project_id: @project.id,
        agent: {
          name: "new_agent",
          title: "New Agent",
          persona: "New persona."
        }
      }
    end

    assert_response :forbidden
  end

  # ====== UPDATE Tests ======

  test "#update updates project agent" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @project_agent.id,
      agent: { title: "Senior PM" }
    }

    assert_response :success
    @project_agent.reload
    assert { @project_agent.title == "Senior PM" }
  end

  test "#update cannot update company agent from project context" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @company_agent.id,
      agent: { title: "Hacked" }
    }

    assert_response :not_found
  end

  test "#update accessible by collaborator" do
    sign_in @collaborator

    patch :update, params: {
      project_id: @project.id,
      id: @project_agent.id,
      agent: { title: "Updated by collaborator" }
    }

    assert_response :success
  end

  test "#update not accessible by non-member" do
    sign_in @other_user

    patch :update, params: {
      project_id: @project.id,
      id: @project_agent.id,
      agent: { title: "Hacked" }
    }

    assert_response :forbidden
  end

  # ====== DESTROY Tests ======

  test "#destroy removes project agent" do
    sign_in @owner

    assert_difference("Agent.count", -1) do
      delete :destroy, params: {
        project_id: @project.id,
        id: @project_agent.id
      }
    end

    assert_response :no_content
  end

  test "#destroy cannot delete company agent from project context" do
    sign_in @owner

    assert_no_difference("Agent.count") do
      delete :destroy, params: {
        project_id: @project.id,
        id: @company_agent.id
      }
    end

    assert_response :not_found
  end

  test "#destroy accessible by collaborator" do
    sign_in @collaborator

    assert_difference("Agent.count", -1) do
      delete :destroy, params: {
        project_id: @project.id,
        id: @project_agent.id
      }
    end

    assert_response :no_content
  end

  test "#destroy not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("Agent.count") do
      delete :destroy, params: {
        project_id: @project.id,
        id: @project_agent.id
      }
    end

    assert_response :forbidden
  end
end
