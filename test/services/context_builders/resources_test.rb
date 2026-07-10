# frozen_string_literal: true

require "test_helper"

class ContextBuilders::ResourcesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, company: @company, connected_by: @user)
  end

  test "applicable returns false when no repos assets or skills" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    builder = ContextBuilders::Resources.new(session)
    assert_not builder.applicable?
  end

  test "applicable returns true with input assets" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    session.input_assets << asset

    builder = ContextBuilders::Resources.new(session.reload)
    assert builder.applicable?
  end

  test "applicable returns true with repositories" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    session.repositories << create(:repository, scope: @project, integration: @integration)

    assert ContextBuilders::Resources.new(session.reload).applicable?
  end

  test "applicable returns true with skills" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    session.skills << create(:skill, scope: @project)

    assert ContextBuilders::Resources.new(session.reload).applicable?
  end

  test "build returns available-resources section" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    session.input_assets << asset

    sections = ContextBuilders::Resources.new(session.reload).build
    assert_equal 1, sections.length
    assert_equal "available-resources", sections.first.tag
    assert_equal :info, sections.first.priority
  end

  test "build renders a repositories table with clone details" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    repo = create(:repository, scope: @project, integration: @integration, full_name: "acme/api",
      source_branch: "develop", purpose: "Backend API")
    session.repositories << repo

    section = ContextBuilders::Resources.new(session.reload).build.first
    content = section.content

    assert_includes content, "## Available Repositories"
    assert_includes content, "| #{repo.id} | acme/api | /workspace/repo/api | develop | Backend API |"
    assert_includes content, "Use the repository **ID**"
  end

  test "build shows an em dash for repositories without a purpose" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    repo = create(:repository, scope: @project, integration: @integration, full_name: "acme/web", purpose: nil)
    session.repositories << repo

    content = ContextBuilders::Resources.new(session.reload).build.first.content

    assert_includes content, "| acme/web | /workspace/repo/web | main | — |"
  end

  test "build omits repositories recorded as failed in session metadata" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    ok_repo = create(:repository, scope: @project, integration: @integration, full_name: "acme/web")
    failed_repo = create(:repository, scope: @project, integration: @integration, full_name: "acme/broken")
    session.repositories << [ ok_repo, failed_repo ]
    session.update!(metadata: { "failed_repos" => [ { "id" => failed_repo.id } ] })

    content = ContextBuilders::Resources.new(session.reload).build.first.content

    assert_includes content, "acme/web"
    assert_not_includes content, "acme/broken"
  end

  test "build lists input assets with their workspace paths" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, scope: @project, created_by: @user, name: "spec.md", folder: "docs")
    session.input_assets << asset

    content = ContextBuilders::Resources.new(session.reload).build.first.content

    assert_includes content, "## Input Assets (pre-loaded in /workspace/assets/)"
    assert_includes content, "- **spec.md** (id: #{asset.id}) → `/workspace/assets/docs/spec.md`"
  end

  test "build includes the public share link for shared input assets" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, scope: @project, created_by: @user, name: "diagram.html")
    asset.share!
    session.input_assets << asset

    content = ContextBuilders::Resources.new(session.reload).build.first.content

    assert_includes content, "public link: #{asset.share_url}"
  end

  test "build summarises skills for adapters that do not embed skill content" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", agent_type: "claude_code")
    skill = create(:skill, scope: @project, title: "Deploy Runbook", source: "acme/skills",
      description: "Ship safely", content: "1. build 2. deploy")
    session.skills << skill

    content = ContextBuilders::Resources.new(session.reload).build.first.content

    assert_includes content, "## Skills"
    assert_includes content, "- **Deploy Runbook** (acme/skills): Ship safely"
    # Summary mode links to skills rather than inlining their full content.
    assert_not_includes content, "1. build 2. deploy"
  end

  test "build merges repositories, assets and skills into one info section" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    session.repositories << create(:repository, scope: @project, integration: @integration, full_name: "acme/api")
    session.input_assets << create(:asset, scope: @project, created_by: @user, name: "spec.md")
    session.skills << create(:skill, scope: @project, title: "Runbook")

    sections = ContextBuilders::Resources.new(session.reload).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "available-resources", section.tag
    assert_equal :info, section.priority
    assert_includes section.content, "## Available Repositories"
    assert_includes section.content, "## Input Assets"
    assert_includes section.content, "## Skills"
  end
end
