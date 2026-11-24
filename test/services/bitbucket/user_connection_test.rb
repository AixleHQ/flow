# frozen_string_literal: true

require "test_helper"

module Bitbucket
  class UserConnectionTest < ActiveSupport::TestCase
    include BitbucketTestHelper

    PROFILE = { uuid: "{6c1f0a4e-0000-4000-8000-0000000000b1}", account_id: "712020:abc", display_name: "Bee Bucket",
                nickname: "bb-user", avatar_url: "https://a.test/bb" }.freeze

    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @credential = create(:oauth_credential, :bitbucket_user, owner: @user, metadata: {})
      @fake = stub_bitbucket!
      @fake.user = PROFILE
      @fake.emails = [ { email: "alt@example.com", is_primary: false, is_confirmed: true },
                       { email: "bee@example.com", is_primary: true, is_confirmed: true } ]
    end

    test "fetch_identity returns the account and its primary confirmed address, storing nothing" do
      identity = UserConnection.fetch_identity("bb-new-token")

      assert_nil @credential.reload.metadata["bitbucket_user"]
      assert_equal "{6c1f0a4e-0000-4000-8000-0000000000b1}", identity["id"]
      assert_equal "bb-user", identity["nickname"]
      assert_equal "Bee Bucket", identity["name"]
      assert_equal "https://a.test/bb", identity["avatar_url"]
      assert_equal "bee@example.com", identity["commit_email"]
    end

    test "an unconfirmed primary address is not used" do
      @fake.emails = [ { email: "bee@example.com", is_primary: true, is_confirmed: false },
                       { email: "alt@example.com", is_primary: false, is_confirmed: true } ]

      identity = UserConnection.fetch_identity("bb-new-token")

      assert_nil UserConnection.commit_email(identity)
    end

    test "the lookup is made with the person's own token" do
      Bitbucket::Api.unstub(:new)
      Bitbucket::Api.expects(:new).with { |credential| credential.token == "bb-new-token" && credential.kind == :access_token }
                    .returns(@fake)

      UserConnection.fetch_identity("bb-new-token")
    end

    test "a failed lookup fails the connection and touches no stored credential" do
      @credential.update!(metadata: { "bitbucket_user" => { "id" => "{old}", "nickname" => "previous" } })
      @fake.fail_on(:current_user, Bitbucket::Error::NotAuthorized.new)

      assert_raises(Oauth::TokenExchangeError) { UserConnection.fetch_identity("bb-new-token") }

      assert @credential.reload.active?
      assert_equal "previous", @credential.metadata.dig("bitbucket_user", "nickname")
    end

    test "identity_for returns a fresh stored identity without a request" do
      stored = { "id" => "{u}", "nickname" => "kept", "commit_email" => "k@example.com", "fetched_at" => Time.current.iso8601 }
      @credential.update!(metadata: { "bitbucket_user" => stored })

      assert_equal stored, UserConnection.identity_for(@credential)
      assert_empty @fake.calls
    end

    test "identity_for refetches one older than a day, and falls back to it when Bitbucket fails" do
      stale = { "id" => "{u}", "nickname" => "stale", "commit_email" => "s@example.com", "fetched_at" => 2.days.ago.iso8601 }
      @credential.update!(metadata: { "bitbucket_user" => stale })

      assert_equal "bb-user", UserConnection.identity_for(@credential)["nickname"]

      @credential.update!(metadata: { "bitbucket_user" => stale })
      @fake.fail_on(:current_user, Bitbucket::Error.new("down"))

      assert_equal stale, UserConnection.identity_for(@credential)
    end

    test "disconnect! deletes the credentials and consents of the person only, with no request" do
      other = create(:oauth_credential, :bitbucket_user, owner: create(:user, :employee, company: @company))
      project = create(:project, company: @company, owner: @user)
      create(:act_as_consent, :own, user: @user, project: project, provider: "bitbucket")

      UserConnection.disconnect!(@user)

      assert_nil OauthCredential.find_by(id: @credential.id)
      assert OauthCredential.exists?(other.id)
      assert_equal 0, ActAsConsent.where(user: @user).count
      assert_empty @fake.calls
    end

    test "disconnect! also deletes a credential of a retired client, without a request" do
      retired = create(:oauth_credential, :bitbucket_user, owner: @user,
                                                           oauth_client: create(:oauth_client, :bitbucket, client_id: "bb-retired"))

      UserConnection.disconnect!(@user)

      assert_nil OauthCredential.find_by(id: retired.id)
      assert_empty @fake.calls
    end

    test "configured? needs both OAuth client values" do
      Settings.bitbucket.oauth.stubs(:client_id).returns("cid")
      Settings.bitbucket.oauth.stubs(:client_secret).returns("")

      assert_not UserConnection.configured?

      Settings.bitbucket.oauth.stubs(:client_secret).returns("secret")

      assert UserConnection.configured?
    end
  end
end
