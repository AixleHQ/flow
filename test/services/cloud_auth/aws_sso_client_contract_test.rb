# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # Pins FakeAwsSsoClient to the real client's surface. Without this the fake silently
  # drifts and every test that leans on it keeps passing against an interface that no
  # longer exists (docs/testing.md R4).
  #
  # This test does NOT hit AWS. It compares signatures and asserts the fake's return
  # shapes are the real client's own value objects.
  class AwsSsoClientContractTest < ActiveSupport::TestCase
    SEAM_METHODS = %i[
      register_client
      start_device_authorization
      create_token
      refresh_token
      list_accounts
      list_account_roles
      role_credentials
    ].freeze

    test "the fake implements every public method of the real client" do
      real = AwsSsoClient.public_instance_methods(false)
      fake = FakeAwsSsoClient.public_instance_methods(false)

      assert_equal SEAM_METHODS.sort, real.sort,
                   "the real client's public surface changed — update SEAM_METHODS and the fake"
      assert_empty real - fake, "FakeAwsSsoClient is missing methods the real client exposes"
    end

    test "every seam method takes the same keyword arguments in both" do
      SEAM_METHODS.each do |name|
        assert_equal keywords(AwsSsoClient, name), keywords(FakeAwsSsoClient, name),
                     "#{name} keyword arguments differ between the real client and the fake"
      end
    end

    test "both constructors require a region" do
      assert_equal [ [ :keyreq, :region ] ], AwsSsoClient.instance_method(:initialize).parameters
      assert_equal [ [ :keyreq, :region ] ], FakeAwsSsoClient.instance_method(:initialize).parameters
      assert_raises(ArgumentError) { AwsSsoClient.new(region: "") }
    end

    test "the fake returns the real client's value objects" do
      fake = FakeAwsSsoClient.new(region: "us-east-1")
      registration = fake.register_client(client_name: "aixle")

      assert_instance_of AwsSsoClient::Registration, registration
      assert_instance_of AwsSsoClient::DeviceAuthorization,
                         fake.start_device_authorization(registration: registration, start_url: "https://x/start")
      assert_instance_of AwsSsoClient::Token,
                         fake.create_token(registration: registration, device_code: "d")
      assert_instance_of AwsSsoClient::Account, fake.list_accounts(access_token: "t").first
      assert_instance_of AwsSsoClient::RoleCredentials,
                         fake.role_credentials(access_token: "t", account_id: "111122223333", role_name: "R")
    end

    test "create_token returns nil while authorization is pending, then a token" do
      fake = FakeAwsSsoClient.new(region: "us-east-1")
      fake.pending_polls = 2
      registration = fake.register_client(client_name: "aixle")

      assert_nil fake.create_token(registration: registration, device_code: "d")
      assert_nil fake.create_token(registration: registration, device_code: "d")
      assert_instance_of AwsSsoClient::Token, fake.create_token(registration: registration, device_code: "d")
      assert_equal 3, fake.call_count(:create_token)
    end

    test "scripted failures raise CloudAuth errors, never vendor errors" do
      fake = FakeAwsSsoClient.new(region: "us-east-1")
      fake.raise_on = { create_token: DeniedError }
      registration = fake.register_client(client_name: "aixle")

      error = assert_raises(DeniedError) { fake.create_token(registration: registration, device_code: "d") }
      assert_kind_of CloudAuth::Error, error
    end

    # The verification URI must be used verbatim: the documented
    # device.sso.<region>.amazonaws.com host does not resolve, so any code that builds
    # or parses this URL is broken by construction. The fake models a per-instance host
    # so a test cannot accidentally encode the wrong assumption.
    test "the fake's verification_uri_complete carries a prefilled user code on a per-instance host" do
      fake = FakeAwsSsoClient.new(region: "us-east-1")
      registration = fake.register_client(client_name: "aixle")
      device = fake.start_device_authorization(registration: registration, start_url: "https://x/start")

      assert_includes device.verification_uri_complete, "user_code=#{device.user_code}"
      assert_not_includes device.verification_uri_complete, "device.sso."
    end

    test "the required registration scope is the one that yields a refresh token" do
      assert_equal %w[sso:account:access], AwsSsoClient::SCOPES
    end

    private

    def keywords(klass, name)
      klass.instance_method(name).parameters.select { |type, _| type == :keyreq }.map(&:last).sort
    end
  end
end
