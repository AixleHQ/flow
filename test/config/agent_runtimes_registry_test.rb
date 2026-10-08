# frozen_string_literal: true

require "test_helper"

# config/agent_runtimes.json is the build matrix in CI and the runtime list in the app.
# These are the places that still have to name every runtime by hand.
class AgentRuntimesRegistryTest < ActiveSupport::TestCase
  RUNTIMES = JSON.parse(Rails.root.join("config/agent_runtimes.json").read).fetch("runtimes").freeze

  test "every runtime has a Dockerfile, and a pinned one takes the pin only as a build arg" do
    RUNTIMES.each do |runtime|
      dockerfile = Rails.root.join(runtime.fetch("dockerfile"))
      assert dockerfile.file?, "#{runtime['id']}: #{dockerfile} does not exist"
      next if runtime.fetch("cli_version").nil?

      assert_match(/^ARG CLI_VERSION$/, dockerfile.read,
                   "#{runtime['id']}: declare `ARG CLI_VERSION` with no default, so the registry is the only pin")
    end
  end

  test "a Dockerfile that verifies per-release checksums has a pair for its pin" do
    RUNTIMES.each do |runtime|
      version = runtime.fetch("cli_version")
      dockerfile = Rails.root.join(runtime.fetch("dockerfile")).read
      next if version.nil? || !dockerfile.include?('case "${CLI_VERSION}/$arch" in')

      arches = dockerfile.scan(%r{^\s*#{Regexp.escape(version)}/(\w+)\)\s+sha256="\h{64}"}).flatten

      assert_equal 2, arches.uniq.size,
                   "#{runtime['id']}: add the #{version} checksum for both architectures to #{runtime['dockerfile']}"
    end
  end

  test "every runtime has an image override setting and both launch commands" do
    ids = AgentRuntime.ids.sort

    assert_equal ids, Settings.agents.images.to_h.keys.map(&:to_s).sort
    assert_equal ids, ContainerStrategies::AgentBaseStrategy::AUTH_COMMANDS.keys.sort
    assert_equal ids, ContainerStrategies::AgentBaseStrategy::SESSION_COMMANDS.keys.sort
  end

  test "the app's runtime list is the registry's, in its order" do
    assert_equal RUNTIMES.pluck("id"), CompanyMembership::AVAILABLE_AGENTS
    assert_equal "claude-code", AgentRuntime.fetch(:claude_code).image
    assert_raises(KeyError) { AgentRuntime.fetch("unknown_cli") }
  end
end
