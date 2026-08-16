# frozen_string_literal: true

require "test_helper"

class Tools::RegistryTest < ActiveSupport::TestCase
  # Filesystem cross-check (no name list to maintain): every InternalTools
  # handler file that declares a tool block must be discovered, and vice
  # versa. Catches a silent eager_load_namespace miss — Zeitwerk deliberately
  # does nothing when a namespace isn't managed.
  test "discovers exactly the handler files that declare tool blocks" do
    handler_files = Dir[Rails.root.join("app/services/internal_tools/*.rb")] +
                    Dir[Rails.root.join("app/services/personal_tools/*.rb")]
    declared = handler_files.select { |f| File.read(f).match?(/^\s+tool do$/) }
                            .map { |f| File.basename(f, ".rb") }

    assert_equal declared.sort, Tools::Registry.names.sort
    assert_operator Tools::Registry.names.size, :>=, 49
  end

  test "fetch returns a frozen definition with a resolvable handler" do
    definition = Tools::Registry.fetch("slack_post_message")

    assert definition.frozen?
    assert_equal "Slack Post Message", definition.display_name
    assert_equal InternalTools::SlackPostMessage, definition.handler_class
    assert_equal %i[messaging slack], definition.tags
    assert_equal "slack", definition.requires_integration.to_s
    assert_nil Tools::Registry.fetch("nope_not_a_tool")
  end

  test "tagged returns builder tools for the Aixle Builder attach path" do
    builder_tools = Tools::Registry.tagged(:builder)

    assert_equal 30, builder_tools.size
    assert builder_tools.all? { |d| d.name.start_with?("meta_") }
    assert builder_tools.none?(&:user_attachable)
  end

  test "injectable covers the auto-injection rule groups" do
    rules = Tools::Registry.injectable.flat_map(&:inject_rules).uniq.sort

    assert_equal %i[coder_integration_connected config_items_attached container_tools_present
                    github_repositories_attached non_interactive_session workflow_step_session], rules
  end

  test "grouping axes cover every definition" do
    defs = Tools::Registry.definitions.values

    assert_equal 30, defs.count { |d| d.tags.include?(:builder) }
    assert_equal 19, defs.count { |d| d.inject_rules.include?(:workflow_step_session) }
    assert_equal 3, defs.count { |d| d.inject_rules.intersect?(%i[container_tools_present non_interactive_session]) }
  end
end
