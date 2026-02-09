# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::SkillsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)

    @skill = @company.skills.create!(
      name: "coding-standards",
      title: "Coding Standards",
      content: "Follow these coding standards...",
      description: "Company-wide coding standards"
    )
  end

  # ====== INDEX Tests ======

  test "#index returns company skills for admin" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["name"] == "coding-standards" }
  end

  test "#index does not return other company skills" do
    @other_company.skills.create!(
      name: "other-skill",
      title: "Other Skill",
      content: "Other content"
    )
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    names = json["items"].map { |i| i["name"] }
    refute { names.include?("other-skill") }
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

  test "#create creates skill" do
    sign_in @admin

    assert_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "new-skill",
          title: "New Skill",
          content: "New skill content",
          description: "New skill description"
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    skill = Skill.find(json["data"]["id"])
    assert { skill.name == "new-skill" }
    assert { skill.title == "New Skill" }
    assert { skill.content == "New skill content" }
    assert { skill.scope == @company }
    assert { skill.custom? }
  end

  test "#create auto-normalizes name" do
    sign_in @admin

    post :create, params: {
      skill: {
        name: "My Skill Name",
        title: "My Skill",
        content: "Content"
      }
    }

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "my_skill_name" }
  end

  test "#create validates name format" do
    sign_in @admin

    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "123invalid",
          title: "Test",
          content: "Test content"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create validates name uniqueness within scope" do
    sign_in @admin

    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "coding-standards",
          title: "Another",
          content: "Another content"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create requires title for custom skill" do
    sign_in @admin

    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "no-title",
          content: "Content"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["title"].present? }
  end

  test "#create requires content for custom skill" do
    sign_in @admin

    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "no-content",
          title: "Title"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["content"].present? }
  end

  test "#create requires admin role" do
    sign_in @employee

    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "new-skill",
          title: "New Skill",
          content: "Content"
        }
      }
    end

    assert_response :forbidden
  end

  test "#create requires authentication" do
    assert_no_difference("Skill.count") do
      post :create, params: {
        skill: {
          name: "new-skill",
          title: "New Skill",
          content: "Content"
        }
      }
    end

    assert_response :unauthorized
  end

  # ====== UPDATE Tests ======

  test "#update updates skill fields" do
    sign_in @admin

    patch :update, params: {
      id: @skill.id,
      skill: {
        title: "Updated Title",
        content: "Updated content"
      }
    }

    assert_response :success
    @skill.reload
    assert { @skill.title == "Updated Title" }
    assert { @skill.content == "Updated content" }
  end

  test "#update cannot change skill from another company" do
    other_skill = @other_company.skills.create!(
      name: "other-skill",
      title: "Other Skill",
      content: "Other content"
    )
    sign_in @admin

    patch :update, params: {
      id: other_skill.id,
      skill: { title: "Hacked" }
    }

    assert_response :not_found
  end

  test "#update requires admin role" do
    sign_in @employee

    patch :update, params: {
      id: @skill.id,
      skill: { title: "Hacked" }
    }

    assert_response :forbidden
  end

  test "#update requires authentication" do
    patch :update, params: {
      id: @skill.id,
      skill: { title: "Hacked" }
    }

    assert_response :unauthorized
  end

  # ====== DESTROY Tests ======

  test "#destroy removes skill" do
    sign_in @admin

    assert_difference("Skill.count", -1) do
      delete :destroy, params: { id: @skill.id }
    end

    assert_response :no_content
    assert { Skill.find_by(id: @skill.id).nil? }
  end

  test "#destroy cannot delete skill from another company" do
    other_skill = @other_company.skills.create!(
      name: "other-skill",
      title: "Other Skill",
      content: "Other content"
    )
    sign_in @admin

    assert_no_difference("Skill.count") do
      delete :destroy, params: { id: other_skill.id }
    end

    assert_response :not_found
  end

  test "#destroy requires admin role" do
    sign_in @employee

    assert_no_difference("Skill.count") do
      delete :destroy, params: { id: @skill.id }
    end

    assert_response :forbidden
  end

  test "#destroy requires authentication" do
    assert_no_difference("Skill.count") do
      delete :destroy, params: { id: @skill.id }
    end

    assert_response :unauthorized
  end

  # ====== Response Format Tests ======

  test "#create returns expected fields" do
    sign_in @admin

    post :create, params: {
      skill: {
        name: "response-test",
        title: "Response Test Skill",
        content: "Response test content",
        description: "Response test description"
      }
    }

    assert_response :created
    json = response.parsed_body
    data = json["data"]
    assert { data["id"].present? }
    assert { data["name"] == "response-test" }
    assert { data["title"] == "Response Test Skill" }
    assert { data["content"] == "Response test content" }
    assert { data["description"] == "Response test description" }
    assert { data["kind"] == "custom" }
    assert { data["scope_type"] == "Company" }
    assert { data["scope_id"] == @company.id }
    assert { data["scope_indicator"] == "company" }
    assert { data["internal"] == false }
    assert { data["created_at"].present? }
    assert { data["updated_at"].present? }
  end
end
