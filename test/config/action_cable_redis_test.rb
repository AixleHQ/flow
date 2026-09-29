# frozen_string_literal: true

require "test_helper"

# Deployed environments run Action Cable on Redis; the test env runs it on the
# `test` adapter, so without this nothing in the suite ever loads the Redis one.
# Loading it is what checks the installed redis gem against the versions the
# adapter accepts — the check a redis 6 bump would otherwise fail only at boot.
class ActionCableRedisTest < ActiveSupport::TestCase
  test "the deployed cable adapter loads with the bundled redis gem" do
    assert_nothing_raised { require "action_cable/subscription_adapter/redis" }
  end

  test "every deployed environment runs cable on Redis" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/cable.yml").read).result, aliases: true)

    %w[staging production].each { |env| assert_equal "redis", config.dig(env, "adapter"), env }
  end
end
