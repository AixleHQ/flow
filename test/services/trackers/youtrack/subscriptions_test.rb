# frozen_string_literal: true

require "test_helper"

class Trackers::Youtrack::SubscriptionsTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    @integration = create(:integration, :youtrack, :active)
    @subscriptions = Trackers::Youtrack::Subscriptions.new(@integration)
  end

  test "each project gets an app subscription with a secret of Aixle's, kept across ensures" do
    first = @subscriptions.ensure!
    again = @subscriptions.ensure!

    assert_equal [ [ APP, "app", "pending" ], [ OPS, "app", "pending" ] ], first.map { |s| [ s.external_scope_id, s.strategy, s.status ] }
    assert_equal first.map(&:secret), again.map(&:secret)
    assert first.all? { |s| s.secret.match?(/\A\h{64}\z/) }
  end

  test "a project dropped from the connection stops receiving" do
    @subscriptions.ensure!
    @integration.update!(settings: @integration.settings.merge("youtrack_projects" => @integration.settings["youtrack_projects"].first(1)))

    Trackers::Youtrack::Subscriptions.new(@integration).ensure!

    assert_equal({ APP => "pending", OPS => "disabled" }, @integration.tracker_subscriptions.pluck(:external_scope_id, :status).to_h)
  end
end
