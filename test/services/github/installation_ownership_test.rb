# frozen_string_literal: true

require "test_helper"

module Github
  # Contract test for the adapter: the two GitHub calls it makes, with the
  # payload shapes GitHub returns.
  class InstallationOwnershipTest < ActiveSupport::TestCase
    setup do
      Settings.github.stubs(:client_id).returns("Iv1.client")
      Settings.github.stubs(:client_secret).returns("client-secret")
    end

    def stub_code_exchange(access_token: "ghu_user_token")
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(status: 200, body: { access_token: access_token, token_type: "bearer", scope: "" }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    def stub_user_installations(ids)
      stub_request(:get, %r{\Ahttps://api\.github\.com/user/installations})
        .with(headers: { "Authorization" => "token ghu_user_token" })
        .to_return(status: 200,
                   body: { total_count: ids.size, installations: ids.map { |id| { id: id, account: { login: "acme" } } } }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    test "is enforced only when the App's OAuth client is configured" do
      assert InstallationOwnership.enforced?

      Settings.github.stubs(:client_secret).returns("")
      assert_not InstallationOwnership.enforced?
    end

    test "confirms an installation the installing user can see" do
      stub_code_exchange
      stub_user_installations([ 111, 222 ])

      assert InstallationOwnership.new(code: "the-code").includes?("222")
    end

    test "refuses an installation the user cannot see" do
      stub_code_exchange
      stub_user_installations([ 111 ])

      assert_not InstallationOwnership.new(code: "the-code").includes?(222)
    end

    test "refuses without a code, and when GitHub rejects the code" do
      assert_not InstallationOwnership.new(code: nil).includes?(222)

      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(status: 200, body: { error: "bad_verification_code" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      assert_not InstallationOwnership.new(code: "stale").includes?(222)
    end
  end
end
