# frozen_string_literal: true

# A project's AWS OIDC integration (docs/design/aws-oidc-integration.md §8). Disconnecting
# keeps the issuer and the roles and makes the issuer answer 404, so STS refuses every
# token until it is connected again; removing it is the Integrations page's own Remove.
class Web::Company::Projects::AwsOidcController < Web::Company::Projects::ApplicationController
  def connect
    integration = Integration.find_or_initialize_by(company: current_project.company, project: current_project,
                                                    provider: "aws_oidc")
    integration.assign_attributes(name: "AWS OIDC", status: "active", connected_by: integration.connected_by || current_user)
    if integration.save
      redirect_to integrations_page, notice: "AWS OIDC connected"
    else
      redirect_to integrations_page, alert: integration.errors.full_messages.to_sentence
    end
  end

  def disconnect
    connection!.update!(status: "inactive")
    redirect_to integrations_page, notice: "AWS OIDC disconnected: AWS now refuses every token from this project"
  end

  private

  def connection!
    Integration.find_by!(project: current_project, provider: "aws_oidc")
  end

  def integrations_page
    company_project_integrations_path(current_project)
  end
end
