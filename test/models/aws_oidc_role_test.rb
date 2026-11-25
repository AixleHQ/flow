# frozen_string_literal: true

require "test_helper"

class AwsOidcRoleTest < ActiveSupport::TestCase
  test "a role names a profile, an IAM role ARN, a region and a duration AWS accepts" do
    role = build(:aws_oidc_role)
    assert role.valid?, role.errors.full_messages.to_sentence
    assert_equal "123456789012", role.account_id

    { name: "Prod Diag", role_arn: "arn:aws:iam::123:role/x", region: "Europe", session_duration_seconds: 60 }
      .each do |attribute, value|
        invalid = build(:aws_oidc_role, attribute => value)
        assert_not invalid.valid?, "#{attribute}=#{value.inspect} should be refused"
        assert invalid.errors[attribute].any?
      end
  end

  test "an ARN in another partition is accepted" do
    assert build(:aws_oidc_role, role_arn: "arn:aws-us-gov:iam::123456789012:role/path/diag").valid?
  end

  test "names are unique within an integration" do
    role = create(:aws_oidc_role, name: "prod-diag")

    assert_not build(:aws_oidc_role, integration: role.integration, name: "prod-diag").valid?
    assert build(:aws_oidc_role, name: "prod-diag").valid?
  end

  test "a role belongs only to an AWS OIDC integration" do
    company = create(:company)
    project = create(:project, company: company, owner: create(:user, company: company))
    github = create(:integration, company: company, project: project)

    assert_not build(:aws_oidc_role, integration: github).valid?
  end

  test "for_project finds the roles of that project's integration only" do
    role = create(:aws_oidc_role)
    other = create(:aws_oidc_role)

    assert_equal [ role ], AwsOidcRole.for_project(role.project).to_a
    assert_not_includes AwsOidcRole.for_project(role.project), other
  end
end

class IntegrationAwsOidcTest < ActiveSupport::TestCase
  test "connecting assigns a random issuer key once" do
    integration = create(:integration, :aws_oidc)
    key = integration.aws_oidc_issuer_key

    assert_match(/\A[A-Za-z0-9]{32}\z/, key)
    integration.update!(status: "inactive")
    assert_equal key, integration.reload.aws_oidc_issuer_key
  end

  test "an AWS OIDC integration is per project, and one per project" do
    integration = create(:integration, :aws_oidc)

    company_wide = build(:integration, provider: :aws_oidc, company: integration.company, project: nil)
    assert_not company_wide.valid?

    second = build(:integration, provider: :aws_oidc, company: integration.company, project: integration.project)
    assert_not second.valid?
  end

  test "removing the integration removes its roles and their attachments" do
    role = create(:aws_oidc_role)
    workflow = create(:workflow, scope: role.project)
    step = create(:step, workflow: workflow, aws_oidc_role_ids: [ role.id ])

    role.integration.destroy!

    assert_not AwsOidcRole.exists?(role.id)
    assert_empty step.reload.aws_oidc_role_ids
  end
end
