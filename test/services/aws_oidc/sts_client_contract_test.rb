# frozen_string_literal: true

require "test_helper"

module AwsOidc
  # Pins FakeAwsOidcStsClient to the real client's surface, and the real client to STS's
  # wire format through WebMock (docs/testing.md R4). No test here reaches AWS.
  class StsClientContractTest < ActiveSupport::TestCase
    ENDPOINT = "https://sts.eu-west-1.amazonaws.com/"
    ROLE_ARN = "arn:aws:iam::123456789012:role/flow-diagnostics"
    SEAM_METHODS = %i[assume_role_with_web_identity caller_arn].freeze

    test "the fake implements every public method of the real client with the same keywords" do
      assert_equal SEAM_METHODS.sort, StsClient.public_instance_methods(false).sort
      SEAM_METHODS.each do |name|
        assert_equal keywords(StsClient, name), keywords(FakeAwsOidcStsClient, name), "#{name} differs"
      end
      assert_raises(ArgumentError) { StsClient.new(region: "") }
    end

    test "the fake returns the real client's value object" do
      creds = FakeAwsOidcStsClient.new(region: "eu-west-1")
                                  .assume_role_with_web_identity(role_arn: ROLE_ARN, session_name: "s", token: "t",
                                                                 duration_seconds: 900)

      assert_instance_of StsClient::Credentials, creds
    end

    test "AssumeRoleWithWebIdentity is sent unsigned and its answer is parsed" do
      stub = stub_request(:post, ENDPOINT)
             .with { |request| request.headers["Authorization"].nil? && request.body.include?("Action=AssumeRoleWithWebIdentity") }
             .to_return(status: 200, body: assume_role_response, headers: { "Content-Type" => "text/xml" })

      creds = StsClient.new(region: "eu-west-1")
                       .assume_role_with_web_identity(role_arn: ROLE_ARN, session_name: "flow-session-1",
                                                      token: "jwt", duration_seconds: 3600)

      assert_requested stub
      assert_equal "ASIAEXAMPLE", creds.access_key_id
      assert_equal "secret", creds.secret_access_key
      assert_equal "token", creds.session_token
      assert_equal Time.utc(2026, 11, 25, 13, 0, 0), creds.expiration
      assert_equal "arn:aws:sts::123456789012:assumed-role/flow-diagnostics/flow-session-1", creds.assumed_role_arn
    end

    {
      "AccessDenied" => TrustPolicyError,
      "InvalidIdentityToken" => IdentityTokenError,
      "IDPCommunicationError" => IssuerUnreachableError,
      "ValidationError" => RoleConfigurationError,
      "Throttling" => ProviderError
    }.each do |code, error_class|
      test "STS #{code} comes out as #{error_class.name.demodulize}" do
        stub_request(:post, ENDPOINT).to_return(status: 400, body: error_response(code),
                                                headers: { "Content-Type" => "text/xml" })

        error = assert_raises(error_class) do
          StsClient.new(region: "eu-west-1").assume_role_with_web_identity(role_arn: ROLE_ARN, session_name: "s",
                                                                            token: "jwt", duration_seconds: 900)
        end
        assert_equal code, error.aws_code
      end
    end

    private

    def keywords(klass, name)
      klass.instance_method(name).parameters.select { |type, _| %i[keyreq key].include?(type) }
    end

    def assume_role_response
      <<~XML
        <AssumeRoleWithWebIdentityResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleWithWebIdentityResult>
            <SubjectFromWebIdentityToken>workflow:1:step:2</SubjectFromWebIdentityToken>
            <AssumedRoleUser>
              <Arn>arn:aws:sts::123456789012:assumed-role/flow-diagnostics/flow-session-1</Arn>
              <AssumedRoleId>AROAEXAMPLE:flow-session-1</AssumedRoleId>
            </AssumedRoleUser>
            <Credentials>
              <AccessKeyId>ASIAEXAMPLE</AccessKeyId>
              <SecretAccessKey>secret</SecretAccessKey>
              <SessionToken>token</SessionToken>
              <Expiration>2026-11-25T13:00:00Z</Expiration>
            </Credentials>
            <Audience>sts.amazonaws.com</Audience>
          </AssumeRoleWithWebIdentityResult>
          <ResponseMetadata><RequestId>req-1</RequestId></ResponseMetadata>
        </AssumeRoleWithWebIdentityResponse>
      XML
    end

    def error_response(code)
      <<~XML
        <ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <Error><Type>Sender</Type><Code>#{code}</Code><Message>#{code} happened</Message></Error>
          <RequestId>req-2</RequestId>
        </ErrorResponse>
      XML
    end
  end
end
