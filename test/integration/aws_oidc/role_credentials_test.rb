# frozen_string_literal: true

require "test_helper"

# `aixle-aws-creds --role <name>` posts here with the role in a header; the response is
# piped straight into the AWS SDK.
class AwsOidc::RoleCredentialsTest < ActionDispatch::IntegrationTest
  PATH = "/cloud/aws/credentials"

  setup do
    @world = aws_oidc_step_session
    @sts = FakeAwsOidcStsClient.new(region: "eu-west-1")
    AwsOidc::StsClient.stubs(:new).returns(@sts)
    stub_container_runtime
  end

  test "an attached role comes back as a bare credential-process document" do
    post PATH, headers: headers(role: "prod-diag")

    assert_response :ok
    assert_equal "application/json", response.media_type
    doc = JSON.parse(response.body)
    assert_equal 1, doc["Version"]
    assert doc["AccessKeyId"].start_with?("ASIAFAKE")
  end

  test "a role the step does not have is forbidden" do
    post PATH, headers: headers(role: "someone-elses")

    assert_response :forbidden
    assert_equal({ "error" => "not_entitled" }, JSON.parse(response.body))
  end

  test "a trust policy refusal is a bad gateway naming the kind of failure" do
    @sts.raise_on = { assume_role_with_web_identity: AwsOidc::TrustPolicyError.new("denied") }

    post PATH, headers: headers(role: "prod-diag")

    assert_response :bad_gateway
    assert_equal({ "error" => "aws_oidc_trust_policy" }, JSON.parse(response.body))
  end

  test "the session key is still required" do
    post PATH, headers: headers(role: "prod-diag").merge("X-Cloud-Key" => "wrong")

    assert_response :unauthorized
    assert_empty @sts.calls
  end

  private

  def headers(role:)
    session = @world[:session]
    { "X-Session-Id" => session.id.to_s, "X-Cloud-Key" => CloudAuth::SessionKey.generate(session),
      CloudCredentialsController::ROLE_HEADER => role }
  end
end
