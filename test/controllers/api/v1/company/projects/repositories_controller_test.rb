# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class RepositoriesControllerTest < ActionDispatch::IntegrationTest
          setup do
            @company = create(:company, email_domain: "testcompany.com")
            @admin = create(:user, :admin, company: @company)
            @member = create(:user, :employee, company: @company)
            @outsider = create(:user, :employee, company: create(:company))

            @project = create(:project, company: @company, owner: @admin)
            @project.add_collaborator(@member)

            @integration = create(:integration, :github, :active, company: @company, connected_by: @admin)
            @gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @admin)
            @company_repo = create(:repository, :company_scope, full_name: "org/company-repo",
              scope: @company, integration: @integration)
            @project_repo = create(:repository, :project_scope, full_name: "org/project-repo",
              scope: @project, integration: @integration)
            @gitlab_project_repo = create(:repository, :project_scope, full_name: "group/gl-repo",
              scope: @project, integration: @gitlab_integration, webhook_secret: "project-secret-xyz")
          end

          # --- Index ---
          test "index returns merged repositories for project collaborator" do
            sign_in_as @member

            get api_v1_company_project_repositories_path(@project)

            assert_response :success
            items = response.parsed_body["items"]
            assert items.present?
            full_names = items.map { |r| r["full_name"] }
            assert_includes full_names, "org/company-repo"
            assert_includes full_names, "org/project-repo"
          end

          test "index returns scope_indicator for each repo" do
            sign_in_as @member

            get api_v1_company_project_repositories_path(@project)

            assert_response :success
            items = response.parsed_body["items"]
            company_item = items.find { |r| r["full_name"] == "org/company-repo" }
            project_item = items.find { |r| r["full_name"] == "org/project-repo" }
            assert_equal "company", company_item["scope_indicator"]
            assert_equal "project", project_item["scope_indicator"]
          end

          test "index fails for outsider" do
            sign_in_as @outsider

            get api_v1_company_project_repositories_path(@project)

            assert_response :not_found
          end

          test "index requires authentication" do
            get api_v1_company_project_repositories_path(@project)

            assert_response :unauthorized
          end

          # --- Create ---
          test "create adds repository for admin" do
            sign_in_as @admin

            Github::RepositoryService.any_instance.expects(:find_repo).with("org/new-repo").returns({
              full_name: "org/new-repo",
              default_branch: "main",
              clone_url: "https://github.com/org/new-repo.git",
              is_private: false,
              description: "New repo"
            })

            assert_difference("Repository.count", 1) do
              post api_v1_company_project_repositories_path(@project),
                params: { integration_id: @integration.id, full_name: "org/new-repo" }
            end

            assert_response :created
            data = response.parsed_body["data"]
            assert_equal "org/new-repo", data["full_name"]
            assert_equal @project.id, data["scope_id"]
          end

          test "create returns error when repo not found on GitHub" do
            sign_in_as @admin

            Github::RepositoryService.any_instance.expects(:find_repo).returns(nil)

            post api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id, full_name: "org/nonexistent" }

            assert_response :unprocessable_entity
            assert_match(/not found/i, response.parsed_body["error"])
          end

          test "create requires admin" do
            sign_in_as @member

            Github::RepositoryService.any_instance.expects(:find_repo).never

            post api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id, full_name: "org/new" }

            assert_response :forbidden
          end

          # --- Update ---
          test "update repository for admin" do
            sign_in_as @admin

            patch api_v1_company_project_repository_path(@project, @project_repo),
              params: { repository: { source_branch: "develop", purpose: "agent" } }

            assert_response :success
            assert_equal "develop", response.parsed_body["data"]["source_branch"]
            assert_equal "agent", response.parsed_body["data"]["purpose"]
          end

          test "update requires admin" do
            sign_in_as @member

            patch api_v1_company_project_repository_path(@project, @project_repo),
              params: { repository: { source_branch: "develop" } }

            assert_response :forbidden
          end

          # --- Destroy ---
          test "destroy removes repository for admin" do
            sign_in_as @admin
            Github::RepositoryService.any_instance.expects(:remove).once

            assert_difference("Repository.count", -1) do
              delete api_v1_company_project_repository_path(@project, @project_repo)
            end

            assert_response :success
          end

          test "destroy calls remove on gitlab repository" do
            sign_in_as @admin
            Gitlab::RepositoryService.any_instance.expects(:remove).once

            assert_difference("Repository.count", -1) do
              delete api_v1_company_project_repository_path(@project, @gitlab_project_repo)
            end

            assert_response :success
          end

          test "destroy requires admin" do
            sign_in_as @member

            assert_no_difference("Repository.count") do
              delete api_v1_company_project_repository_path(@project, @project_repo)
            end

            assert_response :forbidden
          end

          # --- Available ---
          test "available returns repos for admin" do
            sign_in_as @admin

            Github::RepositoryService.any_instance.expects(:list_available).returns([
              { full_name: "org/app", default_branch: "main", clone_url: "https://...", is_private: false, description: nil }
            ])

            get available_api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id }

            assert_response :success
            assert_equal 1, response.parsed_body["items"].length
          end

          test "available requires admin" do
            sign_in_as @member

            get available_api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id }

            assert_response :forbidden
          end

          # --- Branches ---
          test "branches returns branches for admin" do
            sign_in_as @admin

            Github::RepositoryService.any_instance.expects(:list_branches).with("org/project-repo").returns(%w[main develop])

            get branches_api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id, full_name: "org/project-repo" }

            assert_response :success
            items = response.parsed_body["items"]
            assert_equal 2, items.length
            assert_includes items, "main"
          end

          test "branches requires admin" do
            sign_in_as @member

            get branches_api_v1_company_project_repositories_path(@project),
              params: { integration_id: @integration.id, full_name: "org/repo" }

            assert_response :forbidden
          end

          # --- Create with GitLab ---
          test "create with gitlab integration configures webhook" do
            sign_in_as @admin

            Gitlab::RepositoryService.any_instance.expects(:find_repo).with("group/new-repo").returns({
              full_name: "group/new-repo",
              default_branch: "main",
              clone_url: "https://gitlab.com/group/new-repo.git",
              is_private: false,
              description: "GitLab repo"
            })
            Gitlab::RepositoryService.any_instance.expects(:configure).once

            assert_difference("Repository.count", 1) do
              post api_v1_company_project_repositories_path(@project),
                params: { integration_id: @gitlab_integration.id, full_name: "group/new-repo" }
            end

            assert_response :created
            assert_equal "group/new-repo", response.parsed_body["data"]["full_name"]
          end
        end
      end
    end
  end
end
