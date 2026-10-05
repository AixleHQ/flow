# frozen_string_literal: true

require "test_helper"

class Trackers::Youtrack::SubscriptionsTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    @integration = create(:integration, :youtrack, :active)
    @subscriptions = Trackers::Youtrack::Subscriptions.new(@integration)
  end

  test "each project gets a manual subscription with a token of Aixle's, kept across ensures" do
    first = @subscriptions.ensure!
    again = @subscriptions.ensure!

    assert_equal [ [ APP, "manual", "pending", "X-YouTrack-Token" ], [ OPS, "manual", "pending", "X-YouTrack-Token" ] ],
                 first.map { |s| [ s.external_scope_id, s.strategy, s.status, s.settings["header"] ] }
    assert_equal first.map(&:secret), again.map(&:secret)
    assert first.all? { |s| s.secret.match?(/\A\h{64}\z/) }
  end

  test "a project dropped from the connection stops receiving" do
    @subscriptions.ensure!
    @integration.update!(settings: @integration.settings.merge("youtrack_projects" => @integration.settings["youtrack_projects"].first(1)))

    Trackers::Youtrack::Subscriptions.new(@integration).ensure!

    assert_equal({ APP => "pending", OPS => "disabled" }, @integration.tracker_subscriptions.pluck(:external_scope_id, :status).to_h)
  end

  test "the token a project's app already sends replaces Aixle's, and a short or foreign one is refused" do
    subscription = @subscriptions.use_token!(APP, token: " #{'k' * 32} ", header: "X-Hook")

    assert_equal [ "k" * 32, "X-Hook" ], [ subscription.reload.secret, subscription.settings["header"] ]
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @subscriptions.use_token!(APP, token: "short") }.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @subscriptions.use_token!(APP, token: "k" * 32, header: "Bad Header") }.code
    assert_equal "not_found", assert_raises(Trackers::Error) { @subscriptions.use_token!("0-9", token: "k" * 32) }.code
  end
end
