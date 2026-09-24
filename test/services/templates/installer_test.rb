# frozen_string_literal: true

require "test_helper"

class Templates::InstallerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")

  setup do
    @user = create(:user, :employee, :onboarding_completed)
    @company = @user.companies.first
    create(:tool, :system, name: "board_add_comment")
    @template = catalog_template(Templates::Package.from_directory(FIXTURE))
  end

  def catalog_template(package)
    CatalogTemplate.new.assign_package(package, commit_sha: SecureRandom.hex(20)).tap(&:save!)
  end

  def installer(template: @template, target: { company: @company }, key: "k1", **options)
    Templates::Installer.new(catalog_template: template, user: @user, target: target, idempotency_key: key, **options)
  end

  # A small workflow-kind package, installable into an existing project.
  def workflow_package(persona: "Reviews diffs.")
    Templates::Package.new(definition: {
      "format_version" => 1, "slug" => "pr-review", "version" => 1, "name" => "PR review",
      "agents" => [ { "key" => "reviewer", "name" => "reviewer", "title" => "Reviewer", "persona" => persona } ],
      "workflows" => [ { "key" => "review", "name" => "Review", "steps" => [
        { "key" => "read", "name" => "Read the diff", "agent" => "reviewer", "instructions" => "Read it." }
      ] } ]
    })
  end

  test "a project template installs as a new project with every resource wired by id" do
    result = installer(inputs: { "review_language" => "German" }).apply

    project = result.project
    assert result.created
    assert_equal "Dev team SDLC", project.name
    assert_equal @user, project.owner
    assert_equal "Delivery pipeline for main-based repositories.", project.description
    assert_equal [ "Backlog", "Tech Design", "Code Review", "Done" ], project.board.board_columns.map(&:name)

    agent = project.agents.find_by!(name: "architect")
    assert_equal "Answer in German.", agent.principles
    assert_equal "manual", project.skills.find_by!(name: "house-style").origin
    registry_skill = project.skills.find_by!(name: "code-review")
    assert_equal "acme/skills@code-review", registry_skill.package
    assert_match(/Read the diff/, registry_skill.content)

    linear = project.mcp_servers.find_by!(connector_name: "app.linear/linear")
    assert_equal "https://mcp.linear.app/mcp", linear.url
    sentry = project.mcp_servers.find_by!(name: "Sentry")
    assert_equal({ "X-Org" => "config_item:SENTRY_ORG" }, sentry.headers)
    tool = project.tools.find_by!(name: "run_tests")
    assert_equal [ "/workspace/run.sh" ], tool.tool_files.map(&:path)
    assert_equal "Coding standards", project.assets.sole.name

    assert_equal "main", project.config_items.find_by!(name: "TARGET_BRANCH").value
    assert_nil project.config_items.find_by(name: "SENTRY_TOKEN"), "a secret without a value creates no row"

    workflow = project.workflows.sole
    design, implement = workflow.steps.order(:position).to_a
    assert_equal agent.id, design.agent_id
    assert_equal [ registry_skill.id ], design.skill_ids
    assert_equal [ Tool.find_by!(name: "board_add_comment").id ], design.tool_ids
    assert_equal [ design.id ], implement.depends_on_step_ids
    assert_equal [ linear.id ], implement.mcp_server_ids
    assert_equal "Write the design note in German.", design.instructions
    assert_equal [ sentry.id ], workflow.base_mcp_server_ids
    assert_equal [], workflow.base_config_item_ids
    assert_equal false, workflow.inherit_all_project_resources # rubocop:disable Minitest/RefuteFalse
  end

  test "every trigger is installed inactive and the checklist records how to activate it" do
    project = installer.apply.project

    column_trigger = ColumnWorkflowBinding.joins(board_column: :board).find_by!(boards: { project_id: project.id })
    assert_equal "manual", column_trigger.trigger_mode
    assert_equal "Tech Design", column_trigger.board_column.name
    schedule = project.workflows.sole.trigger_bindings.sole
    assert_equal false, schedule.enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal "Backlog", BoardColumn.find(schedule.subject_column_id).name

    items = project.template_installs.sole.setup_items.index_by(&:ref)
    assert_equal "auto", items["trigger:0"].detail["activate_mode"]
    assert_equal column_trigger.id, items["trigger:0"].detail["trigger_id"]
    sentry = project.mcp_servers.find_by!(name: "Sentry")
    assert_equal %W[integration:github oauth:#{sentry.id} repository:app_repo secret:SENTRY_TOKEN trigger:0 trigger:1],
                 items.keys.sort, "the declared-OAuth server gets its sign-in item at install, before any probe"
    assert_equal [ project.workflows.sole.id ], items["secret:SENTRY_TOKEN"].detail.dig("attach_to", "workflow_ids")
  end

  test "records provenance, counts the install and probes the created servers after commit" do
    assert_enqueued_with(job: Templates::ProbeServersJob) do
      @result = installer.apply
    end

    install = @result.install
    assert_equal [ @template.slug, @template.version, @template.commit_sha, @template.package_digest ],
                 [ install.slug, install.version, install.commit_sha, install.package_digest ]
    assert_equal 1, @template.reload.install_count
  end

  test "a secret typed on the install page becomes an encrypted config item and leaves no checklist entry" do
    project = installer(secrets: { "SENTRY_TOKEN" => "tok-123" }).apply.project

    token = project.config_items.find_by!(name: "SENTRY_TOKEN")
    assert_predicate token, :secret?
    assert_equal "tok-123", token.decrypted_value
    assert_equal [ token.id ], project.workflows.sole.base_config_item_ids
    assert_nil project.template_installs.sole.setup_items.find_by(ref: "secret:SENTRY_TOKEN")
  end

  test "the same idempotency key returns the first install instead of a second project" do
    first = installer.apply

    second = installer.apply

    assert_not second.created
    assert_equal first.install, second.install
    assert_equal 1, @company.projects.where(name: "Dev team SDLC").count
  end

  test "a plan that changed since it was confirmed is refused" do
    project = create(:project, company: @company, owner: @user)
    template = catalog_template(workflow_package)
    confirmed = installer(template: template, target: { project: project }).plan.digest
    create(:agent, scope: project, name: "reviewer", title: "Reviewer", persona: "Reviews diffs.",
                   principles: nil, communication_style: nil)

    assert_raises(Templates::Installer::PlanChanged) do
      installer(template: template, target: { project: project }, confirmed_digest: confirmed).apply
    end
  end

  test "a page opened on an older version is refused" do
    error = assert_raises(Templates::Planner::StaleTemplate) do
      installer(expected: { version: @template.version - 1 }).plan
    end
    assert_match(/changed since you opened it/, error.message)
  end

  test "a revoked template cannot be installed" do
    @template.update!(revoked_at: Time.current, revocation_reason: "Broken image.")

    error = assert_raises(Templates::Planner::NotInstallable) { installer.plan }
    assert_match(/Broken image/, error.message)
  end

  test "a viewer cannot install" do
    @user.company_memberships.update_all(role: "viewer")

    assert_raises(Templates::Planner::NotAllowed) { installer.plan }
  end

  test "a project template never installs into an existing project" do
    project = create(:project, company: @company, owner: @user)

    assert_raises(Templates::Planner::NotAllowed) { installer(target: { project: project }).plan }
  end

  test "into an existing project, an identical agent is reused and a different one is a conflict until resolved" do
    project = create(:project, company: @company, owner: @user)
    existing = create(:agent, scope: project, name: "reviewer", title: "Reviewer", persona: "Something else.",
                              principles: nil, communication_style: nil)
    template = catalog_template(workflow_package)
    target = { project: project }

    assert_equal "conflict", installer(template: template, target: target).plan.item("agents", "reviewer").action
    assert_raises(Templates::Installer::UnresolvedConflicts) { installer(template: template, target: target).apply }

    copied = installer(template: template, target: target, key: "k2", resolutions: { "agents.reviewer" => "copy" }).apply
    copy = project.agents.find_by!(name: "reviewer_2")
    assert_equal copy.id, project.workflows.sole.steps.sole.agent_id
    assert_equal "Reviews diffs.", copy.persona

    existing.update!(persona: "Reviews diffs.")
    reused = installer(template: template, target: target, key: "k3").plan
    assert_equal "reuse", reused.item("agents", "reviewer").action
    assert copied.created
  end

  test "a second workflow install into the same project gets a suffixed name" do
    project = create(:project, company: @company, owner: @user)
    template = catalog_template(workflow_package)

    installer(template: template, target: { project: project }).apply
    installer(template: template, target: { project: project }, key: "k2").apply

    assert_equal [ "Review", "Review (2)" ], project.workflows.order(:id).pluck(:name)
    assert_equal 1, project.agents.count, "the identical agent is reused, not copied"
  end

  test "a board template merges columns into the owner's board and is skipped for anyone else" do
    project = create(:project, company: @company, owner: @user)
    Board.create_from_columns(project: project, name: "Main", columns: [ { name: "Backlog" } ])
    board_template = catalog_template(Templates::Package.new(definition: {
      "format_version" => 1, "slug" => "release-board", "version" => 1, "name" => "Release board",
      "board" => { "columns" => [ { "key" => "backlog", "name" => "Backlog" }, { "key" => "qa", "name" => "QA" } ] }
    }))

    installer(template: board_template, target: { project: project }).apply
    assert_equal %w[Backlog QA], project.board.board_columns.map(&:name)

    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    project.add_collaborator(collaborator)
    result = Templates::Installer.new(catalog_template: board_template, user: collaborator, target: { project: project },
                                      idempotency_key: "c1").apply
    assert_equal %w[Backlog QA], project.board.reload.board_columns.map(&:name)
    assert result.install.setup_items.exists?(kind: "board")
  end
end
