# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaListToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "lists custom and system tools visible for the session's project" do
    company_tool = create(:tool, scope: @project,
                                 name: "company_tool", display_name: "Company Tool")
    project_tool = create(:tool, scope: @project,
                                 name: "project_tool", display_name: "Project Tool")
    system_tool = create(:tool, :system,
                                name: "system_tool", display_name: "System Tool")

    # Tools that must NOT show up for this project's view:
    other_company = create(:company)
    foreign_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    create(:tool, scope: foreign_project, name: "foreign_company_tool")
    other_project = create(:project, company: @company, owner: @user)
    create(:tool, scope: other_project, name: "sibling_project_tool")
    # Soft-deleted tool in-scope — excluded by not_deleted.
    create(:tool, scope: @project, name: "deleted_tool", deleted_at: Time.current)
    # A kind outside the {custom, system} filter — excluded by the kind clause.
    create(:tool, :meta, name: "meta_tool")

    result = InternalTools::MetaListTools.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 3, data["tools_count"]
    assert_equal data["tools_count"], data["tools"].size

    by_id = data["tools"].index_by { |t| t["id"] }
    assert_equal %w[company_tool project_tool system_tool],
                 data["tools"].map { |t| t["name"] }.sort

    assert_equal "Company Tool", by_id[company_tool.id]["display_name"]
    assert_equal "Project", by_id[company_tool.id]["scope_type"]
    assert_equal "custom", by_id[company_tool.id]["kind"]

    assert_equal "Project", by_id[project_tool.id]["scope_type"]
    assert_equal "custom", by_id[project_tool.id]["kind"]

    # System tools are global (nil scope) and reported as kind "system".
    assert_nil by_id[system_tool.id]["scope_type"]
    assert_equal "system", by_id[system_tool.id]["kind"]

    listed_names = data["tools"].map { |t| t["name"] }
    assert_not_includes listed_names, "foreign_company_tool"
    assert_not_includes listed_names, "sibling_project_tool"
    assert_not_includes listed_names, "deleted_tool"
    assert_not_includes listed_names, "meta_tool"
  end

  test "targets an explicit project via project_id param instead of the session project" do
    # Session project has its own project-scoped tool...
    create(:tool, scope: @project, name: "session_project_tool")
    # ...but we ask about a different project in the same company.
    other_project = create(:project, company: @company, owner: @user)
    target_tool = create(:tool, scope: other_project, name: "target_project_tool")
    shared_company_tool = create(:tool, scope: other_project, name: "shared_company_tool")

    result = InternalTools::MetaListTools.new(
      params: { project_id: other_project.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])

    listed_ids = data["tools"].map { |t| t["id"] }
    assert_includes listed_ids, target_tool.id
    assert_includes listed_ids, shared_company_tool.id
    # The session project's own tool is not part of the targeted project's view.
    assert_not_includes data["tools"].map { |t| t["name"] }, "session_project_tool"
    assert_equal 2, data["tools_count"]
  end

  test "returns success with an empty list when no tools are visible" do
    result = InternalTools::MetaListTools.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 0, data["tools_count"]
    assert_equal [], data["tools"]
  end
end
