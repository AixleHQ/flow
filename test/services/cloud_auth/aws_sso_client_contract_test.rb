# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # Pins FakeAwsSsoClient to the real client's surface. Without this the fake silently
  # drifts and every test that leans on it keeps passing against an interface that no
  # longer exists (docs/testing.md R4).
  #
  # No test here hits AWS. Most compare signatures and assert the fake's return shapes
  # are the real client's own value objects; the pagination tests pin the real client to
  # the portal API's wire surface with WebMock (docs/testing.md R4 — the vendor SDK is
  # exercised through HTTP, never stubbed as a constant).
  class AwsSsoClientContractTest < ActiveSupport::TestCase
    PORTAL = "https://portal.sso.us-east-1.amazonaws.com"
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

    # -- portal pagination -----------------------------------------------------
    #
    # An organisation whose user is assigned to more accounts than one page holds gets a
    # truncated list, and a missing account is indistinguishable from one that was never
    # granted. Same for a user holding many permission sets in a single account.

    test "list_accounts follows next_token to the end" do
      stub_accounts_page(nil, accounts: [ account("111122223333", "Prod") ], next_token: "page-2")
      stub_accounts_page("page-2", accounts: [ account("444455556666", "Aixle") ], next_token: nil)

      accounts = client.list_accounts(access_token: "bearer-token")

      assert_equal %w[111122223333 444455556666], accounts.map(&:account_id)
      assert_equal [ "Prod", "Aixle" ], accounts.map(&:account_name)
      assert_requested :get, "#{PORTAL}/assignment/accounts", times: 1
    end

    test "list_accounts sends the bearer token in the portal's own header" do
      stub_accounts_page(nil, accounts: [ account("111122223333", "Prod") ], next_token: nil)

      client.list_accounts(access_token: "bearer-token")

      assert_requested(:get, "#{PORTAL}/assignment/accounts",
                       headers: { "x-amz-sso_bearer_token" => "bearer-token" })
    end

    test "list_account_roles follows next_token to the end" do
      stub_roles_page(nil, roles: %w[BedrockUser], next_token: "page-2")
      stub_roles_page("page-2", roles: %w[ReadOnly], next_token: nil)

      assert_equal %w[BedrockUser ReadOnly],
                   client.list_account_roles(access_token: "bearer-token", account_id: "111122223333")
    end

    # A pathological instance must not turn a connect into an unbounded walk — but the
    # truncation is logged, never silent.
    test "pagination stops at MAX_PAGES and says so" do
      # Regex URL so every page — the query-less first request included — matches the one
      # stub that never stops handing back a next_token.
      stub_request(:get, %r{portal\.sso\.us-east-1\.amazonaws\.com/assignment/accounts})
        .to_return(page_body(accounts: [ account("111122223333", "Prod") ], next_token: "more"))

      Rails.logger.expects(:warn).with { |message| message.to_s.include?("list_accounts truncated") }

      assert_equal AwsSsoClient::MAX_PAGES, client.list_accounts(access_token: "bearer-token").length
    end

    private

    def client
      AwsSsoClient.new(region: "us-east-1")
    end

    def account(id, name)
      { accountId: id, accountName: name, emailAddress: "owner+#{id}@example.com" }
    end

    def page_body(accounts: nil, roles: nil, next_token: nil)
      body = {}
      body[:accountList] = accounts if accounts
      body[:roleList] = roles.map { |r| { accountId: "111122223333", roleName: r } } if roles
      body[:nextToken] = next_token if next_token
      { status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json }
    end

    def stub_accounts_page(token, accounts:, next_token:)
      stub = stub_request(:get, "#{PORTAL}/assignment/accounts")
      stub = stub.with(query: { next_token: token }) if token
      stub.to_return(page_body(accounts: accounts, next_token: next_token))
    end

    def stub_roles_page(token, roles:, next_token:)
      query = { account_id: "111122223333" }
      query[:next_token] = token if token
      stub_request(:get, "#{PORTAL}/assignment/roles")
        .with(query: query)
        .to_return(page_body(roles: roles, next_token: next_token))
    end

    def keywords(klass, name)
      klass.instance_method(name).parameters.select { |type, _| type == :keyreq }.map(&:last).sort
    end
  end
end
