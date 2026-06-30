# frozen_string_literal: true

require "test_helper"

module Integrations
  class ManagedMCPToolRegistryTest < ActiveSupport::TestCase
    test "coder provider is registered with the three managed tool names" do
      names = Integrations::ManagedMCPToolRegistry.tool_names_for("coder")
      assert_equal %w[coder_allocate_machine coder_ssh_exec coder_release_machine].sort, names.sort
    end

    test "unknown providers resolve to an empty list" do
      assert_equal [], Integrations::ManagedMCPToolRegistry.tool_names_for("nope")
      assert_equal [], Integrations::ManagedMCPToolRegistry.tool_names_for(nil)
    end

    test "known? identifies tool names from any registered provider" do
      assert Integrations::ManagedMCPToolRegistry.known?("coder_ssh_exec")
      assert_not Integrations::ManagedMCPToolRegistry.known?("definitely_not_a_tool")
    end
  end
end
