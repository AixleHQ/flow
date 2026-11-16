# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261113130000_strip_reconnect_grace_from_runner_config")

class StripReconnectGraceFromRunnerConfigTest < ActiveSupport::TestCase
  def migrate
    migration = StripReconnectGraceFromRunnerConfig.new
    migration.suppress_messages { migration.up }
  end

  test "a runner that had the key saves without an error afterwards, and keeps its other keys" do
    runner = create(:runner, :manual)
    runner.update_columns(config: { "reconnect_grace" => 600, "auto_update" => false })

    migrate

    runner.reload
    assert_equal({ "auto_update" => false }, runner.config)
    assert runner.update(name: "Renamed"), runner.errors.full_messages.to_sentence
  end

  test "a runner without the key is left as it is" do
    runner = create(:runner, :manual, config: { "container" => { "network" => "host" } })

    migrate

    assert_equal({ "container" => { "network" => "host" } }, runner.reload.config)
  end
end
