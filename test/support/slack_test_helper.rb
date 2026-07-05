# frozen_string_literal: true

# Canonical seam for the Slack boundary (docs/testing.md §4). Mirrors
# TemporalHelper: a test calls `stub_slack_client!` in setup, then asserts against
# the one in-memory `fake_slack` recorder (R3). This is the seam the Slack callers
# migrate onto in Stage B — no `any_instance`, no ad-hoc `Slack::Client.expects`
# per method.
#
# Delegation is an alias-based singleton swap rather than a Mocha `.returns`,
# because Mocha 3.1.0 cannot compute a return value from the call's arguments
# (`returns` stores static values only) — the fake must actually receive the args
# to record them and echo channel/ts back. The swap is torn down automatically in
# teardown (registered from #included when the module is mixed into
# ActiveSupport::TestCase), so it is auto-reset just like a Mocha stub.
module SlackTestHelper
  SLACK_CLIENT_METHODS = %i[exchange_code auth_test post_message upload_files download_file].freeze

  def self.included(base)
    base.teardown { unstub_slack_client! }
  end

  # The single canonical fake for this test.
  def fake_slack
    @fake_slack ||= FakeSlackClient.new
  end

  # Route every Slack::Client class method to `fake_slack`, so production code
  # under test hits the recorder instead of the network. Returns the fake for
  # immediate `.posted_messages`/`.downloads`/... assertions.
  def stub_slack_client!
    return fake_slack if @slack_client_stubbed

    delegate = fake_slack
    singleton = Slack::Client.singleton_class
    SLACK_CLIENT_METHODS.each do |method_name|
      singleton.send(:alias_method, orig_alias(method_name), method_name)
      singleton.send(:define_method, method_name) do |*args, **kwargs|
        delegate.public_send(method_name, *args, **kwargs)
      end
    end
    @slack_client_stubbed = true
    fake_slack
  end

  # Restore the real Slack::Client methods. Idempotent; a no-op when the seam was
  # never installed, so it is safe to run in every test's teardown.
  def unstub_slack_client!
    return unless @slack_client_stubbed

    singleton = Slack::Client.singleton_class
    SLACK_CLIENT_METHODS.each do |method_name|
      singleton.send(:alias_method, method_name, orig_alias(method_name))
      singleton.send(:remove_method, orig_alias(method_name))
    end
    @slack_client_stubbed = false
  end

  private

  def orig_alias(method_name)
    :"__slack_test_helper_orig_#{method_name}"
  end
end
