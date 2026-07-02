# frozen_string_literal: true

require "test_helper"

module Slack
  class OauthTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
    end

    test "sign_state / verify_state round-trips the project id and user id" do
      state = Slack::Oauth.sign_state(@project, @user)
      decoded = Slack::Oauth.verify_state(state)
      assert_equal @project.id, decoded["project_id"]
      assert_equal @user.id, decoded["user_id"]
      assert decoded["nonce"].present?
    end

    test "verify_state returns nil for a tampered or garbage state" do
      assert_nil Slack::Oauth.verify_state("not-a-real-state")
      assert_nil Slack::Oauth.verify_state(nil)
    end

    test "authorize_url carries scopes, redirect_uri and a state that verifies back" do
      url = Slack::Oauth.authorize_url(project: @project, user: @user)

      assert url.start_with?(Slack::Oauth::AUTHORIZE_URL)
      assert_includes url, "scope=app_mentions"
      assert_includes url, "redirect_uri="

      state = URI.decode_www_form(URI(url).query).to_h["state"]
      assert_equal @project.id, Slack::Oauth.verify_state(state)["project_id"]
    end

    test "consume_state_nonce is single-use (rejects replay)" do
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(store)

      decoded = Slack::Oauth.verify_state(Slack::Oauth.sign_state(@project, @user))
      assert Slack::Oauth.consume_state_nonce(decoded["nonce"])     # first use succeeds
      assert_not Slack::Oauth.consume_state_nonce(decoded["nonce"]) # replay rejected
    end
  end
end
