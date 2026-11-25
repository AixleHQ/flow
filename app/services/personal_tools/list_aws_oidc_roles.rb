# frozen_string_literal: true

module PersonalTools
  # The ids `aws_oidc_role_ids` / `base_aws_oidc_role_ids` take
  # (docs/design/aws-oidc-integration.md §7.2). Nothing secret: a role is an ARN.
  class ListAwsOidcRoles < Base
    tool do
      display_name "List AWS Roles"
      description "List the IAM roles of a project's AWS OIDC integration: the ids a workflow or a step " \
                  "attaches with aws_oidc_role_ids / base_aws_oidc_role_ids, each a profile the step's " \
                  "~/.aws/config gets. Says whether the integration is connected. Roles are added on the " \
                  "project's Integrations page, not here."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::AwsOidcPolicy, project: project)
      integration = Integration.find_by(project: project, provider: "aws_oidc")
      success(project_id: project.id, connected: integration&.active? || false,
              issuer_url: integration && AwsOidc::Issuer.url(integration), roles: roles(integration))
    end

    private

    def roles(integration)
      return [] if integration.nil?

      integration.aws_oidc_roles.order(:name).map do |role|
        { id: role.id, name: role.name, role_arn: role.role_arn, account_id: role.account_id, region: role.region,
          session_duration_seconds: role.session_duration_seconds }
      end
    end
  end
end
