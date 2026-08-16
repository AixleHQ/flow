# frozen_string_literal: true

require "test_helper"

class Tools::PersonalMCPTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @all = Tools::Registry.for_audience(:user).map(&:name)
  end

  test "public_url falls back to the app's own protocol and domain" do
    Settings.mcp.stubs(:public_server_url).returns(nil)
    Settings.stubs(:protocol).returns("https")
    Settings.stubs(:domain).returns("flow.example.com")

    assert_equal "https://flow.example.com/mcp", Tools::PersonalMCP.public_url
  end

  test "public_url prefers the explicit override" do
    Settings.mcp.stubs(:public_server_url).returns("https://mcp.example.com/rpc")

    assert_equal "https://mcp.example.com/rpc", Tools::PersonalMCP.public_url
  end

  test "a user with no selection is served every user-audience tool" do
    assert_nil @user.mcp_enabled_tools
    assert_equal @all.sort, Tools::PersonalMCP.definitions_for(@user).map(&:name)
  end

  test "a selection narrows what is served, and stale names simply disappear" do
    @user.update!(mcp_enabled_tools: %w[list_projects gone_in_a_later_release])

    assert_equal %w[list_projects], Tools::PersonalMCP.definitions_for(@user).map(&:name)
  end

  test "an empty selection serves nothing" do
    @user.update!(mcp_enabled_tools: [])

    assert_empty Tools::PersonalMCP.definitions_for(@user)
  end

  test "update_selection! stores the subset it was given, minus names it does not know" do
    Tools::PersonalMCP.update_selection!(@user, %w[list_projects list_companies not_a_tool])

    assert_equal %w[list_companies list_projects], @user.reload.mcp_enabled_tools.sort
  end

  # Storing "everything" as a materialized list would freeze the server at
  # today's surface: a tool shipped next release would arrive switched off for
  # every user who ever opened the picker.
  test "selecting every tool is stored as NULL, so later tools stay on" do
    @user.update!(mcp_enabled_tools: %w[list_projects])

    Tools::PersonalMCP.update_selection!(@user, @all)

    assert_nil @user.reload.mcp_enabled_tools
  end

  test "update_selection! with nil resets to every tool" do
    @user.update!(mcp_enabled_tools: %w[list_projects])

    Tools::PersonalMCP.update_selection!(@user, nil)

    assert_nil @user.reload.mcp_enabled_tools
  end

  test "catalog_groups covers every servable tool exactly once" do
    groups = Tools::PersonalMCP.catalog_groups
    listed = groups.flat_map { |g| g[:tools].map { |t| t[:name] } }

    assert_equal @all.sort, listed.sort
    assert_equal listed.uniq, listed
    assert(groups.all? { |g| g[:title].present? && g[:tools].any? })
  end

  test "catalog_groups describes a tool with its description and read-only hint" do
    entries = Tools::PersonalMCP.catalog_groups.flat_map { |g| g[:tools] }

    read = entries.find { |t| t[:name] == "list_projects" }
    assert read[:read_only]
    assert_match(/projects/i, read[:description])

    # The hint drives the "writes" marker in the picker, so a tool that changes
    # something must not come through as read-only.
    assert_equal false, entries.find { |t| t[:name] == "create_project" }[:read_only] # rubocop:disable Minitest/RefuteFalse
  end
end
