# frozen_string_literal: true

require "test_helper"

class IntegrationResourceSlackTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  test "a Slack row shows the deployment's events URL; other providers have none" do
    slack = create(:integration, provider: :slack, status: :active, company: @company)
    github = create(:integration, provider: :github, company: @company)

    assert_equal "#{Settings.protocol}://#{Settings.domain}/webhooks/slack/events",
                 IntegrationResource.new(slack).to_h["slackRequestUrl"]
    assert_nil IntegrationResource.new(github).to_h["slackRequestUrl"]
  end
end
