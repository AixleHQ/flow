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
    definition = Tools::Registry.fetch("chat_post_message")

    assert definition.frozen?
    assert_equal "Chat Post Message", definition.display_name
    assert_equal InternalTools::ChatPostMessage, definition.handler_class
    assert_equal %i[messaging chat], definition.tags
    assert_equal "chat", definition.requires_integration.to_s
    assert_nil Tools::Registry.fetch("nope_not_a_tool")
  end

  test "session lifecycle and sub-step tools are reserved to the top-level agent" do
    %w[finish_session fail_session mark_sub_step].each do |name|
      assert_includes Tools::Registry.fetch(name).description,
        "Only the top-level agent may call this: a subagent reports back", name
    end
  end

  test "injectable covers the plumbing rule groups only" do
    rules = Tools::Registry.injectable.flat_map(&:inject_rules).uniq.sort

    assert_equal %i[any_session config_items_attached container_tools_present], rules
  end

  test "grouping axes cover every definition" do
    defs = Tools::Registry.definitions.values

    assert_equal %w[fail_session finish_session list_sub_steps mark_sub_step],
                 defs.select { |d| d.inject_rules.include?(:any_session) }.map(&:name).sort
    assert_equal %w[read_tool_result], defs.select { |d| d.inject_rules.include?(:container_tools_present) }.map(&:name)

    # Azure is attached like any other tool: every one of its tools is attachable
    # and none is served by a rule.
    azure = defs.select { |d| d.tags.include?(:azure_devops) }
    assert_equal 17, azure.size
    assert azure.all?(&:user_attachable), "Azure tools must be offered in the picker"
    assert azure.all? { |d| d.inject_rules.empty? }
    assert_includes Tools::Registry.ui_groups.pluck(:tag), "azure_devops"

    assert Tools::Registry.fetch("refresh_github_token").user_attachable

    # The pull_request_* tools are picked, not injected: a workflow or a step attaches
    # the set, and a session without it has none.
    pull_requests = defs.select { |d| d.tags.include?(:pull_requests) }
    assert_equal 10, pull_requests.size
    assert pull_requests.all?(&:user_attachable)
    assert pull_requests.all? { |d| d.inject_rules.empty? }
    assert_includes Tools::Registry.ui_groups.pluck(:tag), "pull_requests"
    assert pull_requests.all? { |d| d.requires_integration.to_s == PullRequests::CAPABILITY }
  end

  test "ui_groups offer one entry per visible tag, session tools only" do
    groups = Tools::Registry.ui_groups

    assert_equal %w[board tracker chat coder github_identity gitlab_identity bitbucket_identity azure_devops pull_requests assets session_supervision], groups.map { |g| g[:tag] }
    assert_equal %w[chat_delete_message chat_post_message chat_read_thread chat_update_message],
                 groups.find { |g| g[:tag] == "chat" }[:tool_names]

    defs = groups.flat_map { |g| g[:tool_names] }.map { |n| Tools::Registry.fetch(n) }

    # A personal (audience :user) tool shares tags with the session ones but has
    # no shadow row, so it must never be pulled into a picker group.
    assert defs.all? { |d| d.audience == :session }, "picker groups must hold session tools only"
    assert defs.all?(&:user_attachable)
  end

  test "no tool carries two picker-visible tags" do
    doubled = Tools::Registry.definitions.values.select do |d|
      d.tags.count { |t| Tools::TagCatalog.ui_visible?(t) } > 1
    end

    assert_empty doubled.map(&:name), "a tool in two picker groups would fight over its own ids"
  end
end
