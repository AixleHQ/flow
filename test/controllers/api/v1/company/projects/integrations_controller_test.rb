# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class IntegrationsControllerTest < ActionDispatch::IntegrationTest
          setup do
            @company = create(:company, email_domain: "testcompany.com")
            @admin = create(:user, :admin, company: @company)
            @member = create(:user, :employee, company: @company)
            @project = create(:project, company: @company, owner: @admin)
            @project.add_collaborator(@member)
          end

          # ====== INDEX ======

          test "index returns integrations visible to project" do
            company_integration = create(:integration, :github, :active, company: @company,
              connected_by: @admin, name: "company-org")
            project_integration = create(:integration, :github, :active, company: @company,
              connected_by: @admin, name: "project-org", project: @project)
            sign_in_as @admin

            get api_v1_company_project_integrations_path(@project)

            assert_response :success
            names = response.parsed_body["items"].map { |i| i["name"] }
            assert_includes names, "company-org"
            assert_includes names, "project-org"
          end

          test "index requires authentication" do
            get api_v1_company_project_integrations_path(@project)
            assert_response :unauthorized
          end

          # ====== CREATE — GitLab ======

          test "create with provider gitlab creates integration with valid PAT" do
            sign_in_as @admin

            mock_service = mock("token_service")
            mock_service.expects(:verify_token).returns({ username: "gitlab-user" })
            Gitlab::TokenService.expects(:new).returns(mock_service)

            assert_difference("Integration.count", 1) do
              post api_v1_company_project_integrations_path(@project),
                params: { provider: "gitlab", personal_access_token: "glpat-valid" }
            end

            assert_response :created
            data = response.parsed_body["data"]
            assert_equal "gitlab-user", data["name"]
            assert_equal "active", data["status"]
            assert_equal "gitlab", data["provider"]
            assert_equal @project.id, data["project_id"]
          end

          test "create with provider gitlab sets error status on invalid PAT" do
            sign_in_as @admin

            Gitlab::TokenService.expects(:new).raises(
              Gitlab::TokenService::AuthenticationError.new("Invalid PAT")
            )

            assert_difference("Integration.count", 1) do
              post api_v1_company_project_integrations_path(@project),
                params: { provider: "gitlab", personal_access_token: "glpat-bad" }
            end

            assert_response :created
            data = response.parsed_body["data"]
            assert_equal "error", data["status"]
            assert_equal "gitlab", data["provider"]
          end

          test "create requires admin" do
            sign_in_as @member

            post api_v1_company_project_integrations_path(@project),
              params: { provider: "gitlab", personal_access_token: "glpat-test" }

            assert_response :forbidden
          end

          # ====== DESTROY ======

          test "destroy removes project-scoped integration" do
            integration = create(:integration, :gitlab, :active, company: @company,
              connected_by: @admin, project: @project)
            sign_in_as @admin

            assert_difference("Integration.count", -1) do
              delete api_v1_company_project_integration_path(@project, integration)
            end

            assert_response :success
          end

          test "destroy requires admin" do
            integration = create(:integration, :gitlab, :active, company: @company,
              connected_by: @admin, project: @project)
            sign_in_as @member

            delete api_v1_company_project_integration_path(@project, integration)

            assert_response :forbidden
          end
        end
      end
    end
  end
end
