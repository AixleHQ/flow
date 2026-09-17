# frozen_string_literal: true

require "test_helper"

class ProjectInsightsSharingTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  test "share_usage_with_insights defaults to false" do
    assert_not @project.share_usage_with_insights?
  end

  test "regenerate_insights_connection_token! requires sharing enabled" do
    assert_raises(ArgumentError) { @project.regenerate_insights_connection_token! }
  end

  test "regenerate_insights_connection_token! stores digest and returns plaintext once" do
    @project.update!(share_usage_with_insights: true)
    token = @project.regenerate_insights_connection_token!

    assert token.start_with?(Project::INSIGHTS_CONNECTION_TOKEN_PREFIX)
    assert @project.insights_connection_configured?
    assert_equal Digest::SHA256.hexdigest(token), @project.insights_connection_token_digest
    assert_nil @project.insights_connection_token_last_used_at
  end

  test "find_by_insights_connection_token resolves a valid token" do
    @project.update!(share_usage_with_insights: true)
    token = @project.regenerate_insights_connection_token!

    assert_equal @project, Project.find_by_insights_connection_token(token)
  end

  test "find_by_insights_connection_token returns nil for blank or wrong prefix" do
    assert_nil Project.find_by_insights_connection_token(nil)
    assert_nil Project.find_by_insights_connection_token("amcp_not_insights")
  end

  test "disabling sharing clears the connection token digest" do
    @project.update!(share_usage_with_insights: true)
    @project.regenerate_insights_connection_token!
    assert @project.insights_connection_configured?

    @project.update!(share_usage_with_insights: false)

    assert_nil @project.reload.insights_connection_token_digest
    assert_nil @project.insights_connection_token_last_used_at
    assert_not @project.insights_connection_configured?
  end

  test "disable_insights_connection_token! clears digest without toggling sharing" do
    @project.update!(share_usage_with_insights: true)
    @project.regenerate_insights_connection_token!

    @project.disable_insights_connection_token!

    assert @project.share_usage_with_insights?
    assert_not @project.insights_connection_configured?
  end

  test "touch_insights_connection_token_last_used! throttles to once per minute" do
    @project.update!(share_usage_with_insights: true)
    @project.regenerate_insights_connection_token!

    freeze_time do
      @project.touch_insights_connection_token_last_used!
      first = @project.reload.insights_connection_token_last_used_at

      travel 30.seconds
      @project.touch_insights_connection_token_last_used!
      assert_equal first, @project.reload.insights_connection_token_last_used_at

      travel 31.seconds
      @project.touch_insights_connection_token_last_used!
      assert_operator @project.reload.insights_connection_token_last_used_at, :>, first
    end
  end
end
