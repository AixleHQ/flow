# frozen_string_literal: true

require "test_helper"

class VersionsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @actor = Versions::Actor.ui(@user)
  end

  test "creating through save! records version 1 with the author and source" do
    agent = @project.agents.new(name: "reviewer", title: "Reviewer", persona: "You review code.")

    version = Versions.save!(agent, actor: @actor) { agent.save! }

    assert_equal 1, version.number
    assert version.created?
    assert_equal @user, version.author
    assert_equal "ui", version.source
    assert_equal "You review code.", version.snapshot["persona"]
    assert_equal @project.id, version.project_id
    assert_equal 1, agent.reload.current_version_number
  end

  test "an entity that predates history gets a baseline before its first change" do
    agent = create(:agent, scope: @project, persona: "Old persona")

    Versions.save!(agent, actor: @actor) { agent.update!(persona: "New persona") }

    baseline, saved = agent.entity_versions.reorder(:number).to_a
    assert baseline.baseline?
    assert_equal "system", baseline.source
    assert_equal "Old persona", baseline.snapshot["persona"]
    assert_equal [ 2, "saved", "New persona", @user ], [ saved.number, saved.event, saved.snapshot["persona"], saved.author ]
  end

  test "a save that changes nothing records nothing" do
    agent = create(:agent, scope: @project)
    Versions.save!(agent, actor: @actor) { agent.update!(title: "Changed") }

    assert_nil Versions.save!(agent, actor: @actor) { agent.update!(title: "Changed") }
    assert_equal 2, agent.reload.current_version_number
  end

  test "a save from a stale base version is refused and changes nothing" do
    agent = create(:agent, scope: @project, title: "Original")
    Versions.save!(agent, actor: @actor) { agent.update!(title: "First edit") }

    error = assert_raises(Versions::StaleVersion) do
      Versions.save!(agent, actor: @actor, base_version: 1) { agent.update!(title: "Lost edit") }
    end
    assert_equal 2, error.current_number
    assert_equal "First edit", agent.reload.title
  end

  test "an edit from the builder session is attributed to the agent's session" do
    session = create(:terminal_session, user: @user, project: @project)
    agent = create(:agent, scope: @project)

    version = Versions.save!(agent, actor: Versions::Actor.mcp(@user, session: session)) { agent.update!(title: "By builder") }

    assert_equal [ "builder", session, @user ], [ version.source, version.terminal_session, version.author ]
  end

  test "revert applies the old snapshot and records it as the newest version" do
    agent = create(:agent, scope: @project, persona: "v1 persona")
    Versions.save!(agent, actor: @actor) { agent.update!(persona: "v2 persona") }
    first = agent.entity_versions.find_by(number: 1)

    reverted = Versions.revert!(agent, to: first, actor: @actor)

    assert_equal "v1 persona", agent.reload.persona
    assert_equal [ 3, "reverted", first ], [ reverted.number, reverted.event, reverted.restored_from ]
  end

  test "revert refuses a version of another entity" do
    agent = create(:agent, scope: @project)
    other = create(:agent, scope: @project)
    Versions.save!(other, actor: @actor) { other.update!(title: "x") }

    assert_raises(ArgumentError) { Versions.revert!(agent, to: other.latest_version, actor: @actor) }
  end

  test "archive is refused while a live workflow step uses the agent, naming the step" do
    agent = create(:agent, scope: @project)
    workflow = create(:workflow, scope: @project, name: "Release")
    create(:step, workflow: workflow, name: "Build", agent: agent)

    error = assert_raises(Versions::InUse) { Versions.archive!(agent, actor: @actor) }
    assert_match(/Release → Build/, error.message)
    assert_not agent.reload.archived?
  end

  test "archive and restore are recorded, and an archived name can be reused" do
    agent = create(:agent, scope: @project, name: "helper")

    archived = Versions.archive!(agent, actor: @actor)
    assert agent.reload.archived?
    assert archived.archived?
    assert_not_includes Agent.visible_for_project(@project), agent

    replacement = create(:agent, scope: @project, name: "helper")
    assert replacement.persisted?

    assert_raises(ActiveRecord::RecordInvalid) { Versions.restore!(agent, actor: @actor) }
    replacement.destroy!
    agent.reload
    restored = Versions.restore!(agent, actor: @actor)
    assert restored.restored?
    assert_not agent.reload.archived?
  end

  test "a tool named in a workflow's base list cannot be archived" do
    tool = create(:tool, scope: @project)
    create(:workflow, scope: @project, name: "Nightly", config: { "base_tool_ids" => [ tool.id ] })

    error = assert_raises(Versions::InUse) { Versions.archive!(tool, actor: @actor) }
    assert_match(/Nightly/, error.message)
  end

  test "restoring a workflow switches back on only the triggers asked for" do
    workflow = create(:workflow, scope: @project)
    kept_off = create(:trigger_binding, workflow: workflow, project: @project, enabled: true)
    back_on = create(:trigger_binding, workflow: workflow, project: @project, enabled: true)

    archived = Versions.archive!(workflow, actor: @actor)
    assert_equal [ kept_off.id, back_on.id ].sort, archived.metadata["disabled_trigger_ids"].sort

    Versions.restore!(workflow, actor: @actor, enable_trigger_ids: [ back_on.id ])
    assert_not workflow.reload.deleted?
    assert back_on.reload.enabled
    assert_not kept_off.reload.enabled
  end

  test "skill snapshots carry the whole directory and revert restores it" do
    skill = create(:skill, scope: @project, files: { "SKILL.md" => "one", "scripts/run.sh" => "echo 1" })
    Versions.save!(skill, actor: @actor) { skill.update!(files: { "SKILL.md" => "two" }) }

    Versions.revert!(skill, to: skill.entity_versions.find_by(number: 1), actor: @actor)

    assert_equal({ "SKILL.md" => "one", "scripts/run.sh" => "echo 1" }, skill.reload.files)
  end
end
