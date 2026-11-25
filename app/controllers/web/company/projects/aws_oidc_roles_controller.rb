# frozen_string_literal: true

# The IAM roles of a project's AWS OIDC integration (docs/design/aws-oidc-integration.md §7.1,
# §8). Roles are entered by hand: Flow holds no permission to list them in the customer's
# account, and Verify is what proves one works.
class Web::Company::Projects::AwsOidcRolesController < Web::Company::Projects::ApplicationController
  requires_feature :aws_oidc

  def create
    role = connection!.aws_oidc_roles.new(role_params.merge(created_by: current_user))
    save_and_redirect(role, "AWS role #{role.name} added")
  end

  def update
    role = role!
    role.assign_attributes(role_params)
    save_and_redirect(role, "AWS role #{role.name} saved")
  end

  def destroy
    role = role!
    role.destroy!
    redirect_to integrations_page, notice: "AWS role #{role.name} removed"
  end

  def verify
    render json: AwsOidc::Verifier.new(role: role!).call.to_h
  end

  private

  def role_params
    params.expect(aws_oidc_role: %i[name role_arn region session_duration_seconds])
  end

  def save_and_redirect(role, notice)
    if role.save
      redirect_to integrations_page, notice: notice
    else
      redirect_to integrations_page, inertia: { errors: role.errors.to_hash(true).transform_values(&:first) }
    end
  end

  def connection!
    @connection ||= Integration.find_by!(project: current_project, provider: "aws_oidc")
  end

  def role!
    connection!.aws_oidc_roles.find(params[:id])
  end

  def integrations_page
    company_project_integrations_path(current_project)
  end
end
