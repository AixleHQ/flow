# frozen_string_literal: true

# Builds the world an AWS OIDC exchange needs: a connected integration, a role, and a
# running workflow step session that has the role attached.
module AwsOidcTestHelper
  def aws_oidc_step_session(role_name: "prod-diag", attach: true)
    company = create(:company)
    user = create(:user, :admin, company: company)
    project = create(:project, company: company, owner: user)
    integration = create(:integration, :aws_oidc, company: company, project: project)
    role = create(:aws_oidc_role, integration: integration, name: role_name)
    workflow = create(:workflow, scope: project)
    step = create(:step, workflow: workflow, aws_oidc_role_ids: attach ? [ role.id ] : [])
    workflow_run = create(:workflow_run, workflow: workflow, project: project, user: user)
    session = create(:terminal_session, :running, user: user, project: project, session_type: "workflow_step")
    create(:step_run, :running, workflow_run: workflow_run, step: step, terminal_session: session)
    { company: company, user: user, project: project, integration: integration, role: role,
      workflow: workflow, step: step, session: session.reload }
  end
end
