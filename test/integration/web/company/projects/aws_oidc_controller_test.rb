# frozen_string_literal: true

require "test_helper"

# Web::Company::Projects::AwsOidcController and AwsOidcRolesController with their policies:
# connecting decides which AWS accounts may trust the project, so it and its roles are the
# project owner's or a company admin's.
class Web::Company::Projects::AwsOidcControllerTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    FeatureFlag.find_or_create_by!(key: "aws_oidc").update!(enabled: true)
  end

  teardown { teardown_authz }

  ROLE_PARAMS = { aws_oidc_role: { name: "prod-diag", role_arn: "arn:aws:iam::123456789012:role/diag",
                                   region: "eu-west-1", session_duration_seconds: 3600 } }.freeze

  test "connecting is the project owner's or a company admin's" do
    expectations = { owner: :allowed_write, admin: :allowed_write, collaborator: :denied, viewer: :denied,
                     stranger: :not_found, foreign_admin: :not_found }
    assert_role_matrix(expectations, transport: :web) do
      post connect_company_project_aws_oidc_path(@project)
    end

    integration = Integration.find_by!(project: @project, provider: "aws_oidc")
    assert integration.active?
    assert_match(/\A[A-Za-z0-9]{32}\z/, integration.aws_oidc_issuer_key)
  end

  test "managing roles follows the same rule" do
    connect!
    expectations = { owner: :allowed_write, admin: :allowed_write, collaborator: :denied, viewer: :denied,
                     stranger: :not_found, foreign_admin: :not_found }
    assert_role_matrix(expectations, transport: :web) do
      AwsOidcRole.where(name: "prod-diag").delete_all
      post company_project_aws_oidc_roles_path(@project), params: ROLE_PARAMS
    end
  end

  test "a company without the flag sees nothing" do
    FeatureFlag.find_by!(key: "aws_oidc").update!(enabled: false)
    sign_in_as(@admin)

    post connect_company_project_aws_oidc_path(@project)

    assert_response :not_found
    assert_not Integration.exists?(project: @project, provider: "aws_oidc")
  end

  test "disconnecting keeps the issuer and the roles, and connecting again revives them" do
    sign_in_as(@admin)
    integration = connect!
    role = create(:aws_oidc_role, integration: integration)
    key = integration.aws_oidc_issuer_key

    delete disconnect_company_project_aws_oidc_path(@project)
    assert_equal "inactive", integration.reload.status

    post connect_company_project_aws_oidc_path(@project)
    assert_equal "active", integration.reload.status
    assert_equal key, integration.aws_oidc_issuer_key
    assert AwsOidcRole.exists?(role.id)
  end

  test "roles are added, edited and removed; an invalid ARN comes back against its field" do
    sign_in_as(@admin)
    connect!

    post company_project_aws_oidc_roles_path(@project), params: ROLE_PARAMS
    role = AwsOidcRole.find_by!(name: "prod-diag")
    assert_equal @admin, role.created_by

    patch company_project_aws_oidc_role_path(@project, role), params: { aws_oidc_role: { region: "us-east-1" } }
    assert_equal "us-east-1", role.reload.region

    patch company_project_aws_oidc_role_path(@project, role), params: { aws_oidc_role: { role_arn: "nope" } }
    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/IAM role ARN/, Array(session["inertia_errors"][:role_arn]).to_sentence)

    delete company_project_aws_oidc_role_path(@project, role)
    assert_not AwsOidcRole.exists?(role.id)
  end

  test "verify reports the assumed role, or what AWS refused" do
    sign_in_as(@admin)
    role = create(:aws_oidc_role, integration: connect!)
    sts = FakeAwsOidcStsClient.new(region: role.region)
    AwsOidc::StsClient.stubs(:new).returns(sts)

    post verify_company_project_aws_oidc_role_path(@project, role)
    result = JSON.parse(response.body)
    assert result["ok"]
    assert_match(%r{assumed-role/flow-diagnostics/flow-verify-#{role.id}}, result["assumed_role_arn"])
    assert_equal "verify:integration:#{role.integration_id}",
                 JWT.decode(sts.calls.first.last[:token], nil, false).first["sub"]

    sts.raise_on = { assume_role_with_web_identity: AwsOidc::TrustPolicyError.new("not authorized") }
    post verify_company_project_aws_oidc_role_path(@project, role)
    result = JSON.parse(response.body)
    assert_not result["ok"]
    assert_equal "trust_policy", result["failure"]
    assert_match(/sts:TagSession/, result["message"])
  end

  test "the integrations page carries what the dialog needs and no secret" do
    sign_in_as(@admin)
    role = create(:aws_oidc_role, integration: connect!)

    Bullet.enable = false
    get company_project_integrations_path(@project)

    props = inertia.props[:awsOidc]
    assert props[:enabled]
    assert props[:canManage]
    connection = props[:connection]
    assert_equal AwsOidc::Issuer.url(role.integration), connection[:issuerUrl]
    assert_equal [ role.name ], connection[:roles].map { |r| r[:name] }
    assert_equal "123456789012", connection[:roles].first[:accountId]
  ensure
    Bullet.enable = true
  end

  private

  def connect!
    Integration.find_by(project: @project, provider: "aws_oidc") ||
      create(:integration, :aws_oidc, company: @company, project: @project)
  end
end
