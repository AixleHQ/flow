# frozen_string_literal: true

require "test_helper"

module Gitlab
  class AppConfigTest < ActiveSupport::TestCase
    GITLAB_COM = "https://gitlab.com/api/v4"

    def gitlab_settings(endpoint: GITLAB_COM, webhook_base_url: nil)
      Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: endpoint, webhook_base_url: webhook_base_url))
    end

    test "the hook goes to the deployment's own domain by default" do
      gitlab_settings
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("flow.example.com")

      assert_equal "https://flow.example.com/webhooks/gitlab", AppConfig.webhook_url
      assert AppConfig.webhooks_enabled?
    end

    test "GITLAB_WEBHOOK_BASE_URL wins, for a domain GitLab cannot reach" do
      gitlab_settings(webhook_base_url: "https://tunnel.ngrok-free.dev/")
      Settings.stubs(:protocol).returns("http")
      Settings.stubs(:domain).returns("localhost:4000")

      assert_equal "https://tunnel.ngrok-free.dev/webhooks/gitlab", AppConfig.webhook_url
      assert AppConfig.webhooks_enabled?
    end

    test "gitlab.com cannot reach a loopback or private host, so no hook is registered there" do
      gitlab_settings
      Settings.stubs(:protocol).returns("http")

      {
        "localhost:4000" => "the development default",
        "127.0.0.1:4000" => "loopback by address",
        "10.1.2.3" => "a private range",
        "192.168.1.10:3000" => "another private range",
        "172.16.0.9" => "the awkward private range",
        "web.local" => "an mDNS name",
        "flow.corp.internal" => "an internal name"
      }.each do |domain, why|
        Settings.stubs(:domain).returns(domain)

        assert_not AppConfig.webhooks_enabled?, "#{domain} (#{why}) should register no hook"
      end
    end

    # GitLab inside the same private network can deliver to a private host, but
    # its own loopback is never ours.
    test "a self-managed GitLab on a private host may reach a private deployment" do
      gitlab_settings(endpoint: "https://gitlab.corp.internal/api/v4")
      Settings.stubs(:protocol).returns("https")

      Settings.stubs(:domain).returns("flow.corp.internal")
      assert AppConfig.webhooks_enabled?

      Settings.stubs(:domain).returns("localhost:4000")
      assert_not AppConfig.webhooks_enabled?
    end
  end
end
