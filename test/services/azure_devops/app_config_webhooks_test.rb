# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Where Azure is told to post, and when we let it be told at all.
  #
  # This had its own environment variable with no default, while the comment
  # beside it claimed it defaulted to the deployment's domain. A production
  # deployment with DOMAIN set correctly therefore had Service Hooks silently
  # off, and its CI gates always closed on the five-minute recovery sweep with
  # nothing anywhere saying why.
  class AppConfigWebhooksTest < ActiveSupport::TestCase
    setup { with_azure_devops_enabled }

    test "falls back to the deployment's own domain, like every other webhook here" do
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("flow.example.com")

      assert_equal "https://flow.example.com", AppConfig.webhook_base_url
      assert AppConfig.webhooks_enabled?
    end

    test "an explicit base url wins, for a domain Azure cannot resolve" do
      with_azure_devops_enabled(webhook_base_url: "https://tunnel.ngrok-free.dev")
      Settings.stubs(:domain).returns("flow.example.com")

      assert_equal "https://tunnel.ngrok-free.dev", AppConfig.webhook_base_url
      assert AppConfig.webhooks_enabled?
    end

    # A subscription pointing somewhere Azure cannot reach is worse than none:
    # Azure accepts it, reports it enabled, and fails every delivery quietly.
    test "a host Azure cannot reach provisions nothing" do
      Settings.stubs(:protocol).returns("http")

      {
        "localhost:4000" => "the development default",
        "127.0.0.1:4000" => "loopback by address",
        "10.1.2.3" => "a private range",
        "192.168.1.10:3000" => "another private range",
        "172.16.0.9" => "the awkward private range",
        "web.local" => "an mDNS name"
      }.each do |domain, why|
        Settings.stubs(:domain).returns(domain)

        assert_not AppConfig.webhooks_enabled?, "#{domain} (#{why}) should not provision subscriptions"
      end
    end

    test "a public host on an unusual port is still reachable" do
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("flow.example.com:8443")

      assert AppConfig.webhooks_enabled?
    end
  end
end
