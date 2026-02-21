# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class SkillsControllerTest < ActionDispatch::IntegrationTest
          setup do
            @company = create(:company)
            @owner = create(:user, :employee, company: @company)
            @member = create(:user, :employee, company: @company)
            @outsider = create(:user, :employee, company: create(:company))

            @project = create(:project, company: @company, owner: @owner)
            @project.add_collaborator(@member)

            # Create skills at different scopes
            @internal_skill = create(:skill, :internal, name: "a-internal")
            @company_skill = create(:skill, name: "b-company", scope: @company)
            @project_skill = create(:skill, name: "c-project", scope: @project)
          end

          # --- Index (Merged List) ---
          test "index returns merged list with internal skills" do
            sign_in_as @member
            get api_v1_company_project_skills_path(@project)

            assert_response :success
            skills = response.parsed_body["items"]

            assert_equal 3, skills.count
            names = skills.map { |s| s["name"] }
            assert_includes names, "a-internal"
            assert_includes names, "b-company"
            assert_includes names, "c-project"
          end

          test "index returns correct scope_indicators" do
            sign_in_as @member
            get api_v1_company_project_skills_path(@project)

            assert_response :success
            skills = response.parsed_body["items"]

            internal = skills.find { |s| s["name"] == "a-internal" }
            company = skills.find { |s| s["name"] == "b-company" }
            project = skills.find { |s| s["name"] == "c-project" }

            assert_equal "internal", internal["scope_indicator"]
            assert_equal true, internal["internal"]
            assert_equal "company", company["scope_indicator"]
            assert_equal false, company["internal"]
            assert_equal "project", project["scope_indicator"]
            assert_equal false, project["internal"]
          end

          test "index shows override indicator when project overrides company" do
            create(:skill, name: "b-company", scope: @project)

            sign_in_as @member
            get api_v1_company_project_skills_path(@project)

            assert_response :success
            skills = response.parsed_body["items"]

            shared = skills.select { |s| s["name"] == "b-company" }
            assert_equal 1, shared.count
            assert_equal "overrides_company", shared.first["scope_indicator"]
            assert_equal "Project", shared.first["scope_type"]
          end

          test "index fails for outsider" do
            sign_in_as @outsider
            get api_v1_company_project_skills_path(@project)

            assert_response :not_found
          end

          # --- Create ---
          test "create project skill" do
            sign_in_as @member

            assert_difference "Skill.count" do
              post api_v1_company_project_skills_path(@project), params: {
                skill: {
                  name: "new-project-skill",
                  title: "New Project Skill",
                  content: "New content"
                }
              }
            end

            assert_response :created
            skill = response.parsed_body["data"]
            assert_equal "new-project-skill", skill["name"]
            assert_equal "Project", skill["scope_type"]
            assert_equal @project.id, skill["scope_id"]
          end

          test "create fails for outsider" do
            sign_in_as @outsider

            post api_v1_company_project_skills_path(@project), params: {
              skill: {
                name: "hacked-skill",
                title: "Hacked",
                content: "Content"
              }
            }

            assert_response :not_found
          end

          # --- Update ---
          test "update project skill" do
            sign_in_as @member

            patch api_v1_company_project_skill_path(@project, @project_skill), params: {
              skill: {
                title: "Updated Project Skill"
              }
            }

            assert_response :success
            assert_equal "Updated Project Skill", response.parsed_body["data"]["title"]
          end

          test "update fails for outsider" do
            sign_in_as @outsider

            patch api_v1_company_project_skill_path(@project, @project_skill), params: {
              skill: { title: "Hacked" }
            }

            assert_response :not_found
          end

          # --- Destroy ---
          test "destroy project skill" do
            sign_in_as @member

            assert_difference "Skill.count", -1 do
              delete api_v1_company_project_skill_path(@project, @project_skill)
            end

            assert_response :no_content
          end

          test "destroy fails for outsider" do
            sign_in_as @outsider

            delete api_v1_company_project_skill_path(@project, @project_skill)

            assert_response :not_found
          end
        end
      end
    end
  end
end
