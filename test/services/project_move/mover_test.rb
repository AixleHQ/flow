# frozen_string_literal: true

require "test_helper"

class ProjectMove::MoverTest < ActiveSupport::TestCase
  setup do
    @s = ProjectMoveScenario.new.build
    @super_admin = create(:user, :super_admin)
  end

  test "moves the project and everything it owns into the target, keeping every id" do
    task_numbers = [ @s.parent_task.reload.number, @s.child_task.reload.number ]
    ChatConnectCode.issue!(project: @s.project, provider: "slack", user: @s.owner, channel: "#deploys")

    report = move(member_policy: "add")

    project = @s.project.reload
    assert_equal @s.target, project.company
    assert_equal [ "Launchpad (2)", "launchpad-2" ], [ project.name, project.slug ]
    assert_equal @s.owner, project.owner
    assert_equal task_numbers, [ @s.parent_task.reload.number, @s.child_task.reload.number ]
    assert_equal @s.parent_task, @s.child_task.parent_task
    assert_equal @s.board, project.board
    assert_equal @s.parent_task, @s.comment.reload.board_task
    assert_equal "launchpad-deploy", @s.webhook_endpoint.reload.slug
    assert_equal [ @s.schedule_binding.id, @s.chat_binding.id ].sort, TriggerBinding.where(project: project).ids.sort
    assert_equal [ false, nil ], [ @s.chat_binding.reload.enabled, @s.chat_binding.chat_conversation ],
                 "a channel is the source company's, so the chat trigger waits for one of the target's"
    assert_equal 0, ChatConnectCode.where(project: project).count
    assert_equal "completed", @s.completed_run.reload.state
    assert_equal "DEPLOY_TOKEN", @s.config_item.reload.name

    stale = (ProjectMove::Mover::SCOPED + ProjectMove::Mover::DENORMALIZED).select do |model|
      model.where(project_id: project.id).where.not(company_id: @s.target.id).exists?
    end
    assert_empty stale.map(&:table_name)
    assert_equal @s.target.id, @s.finished_session.reload.company_id
    assert_equal @s.target.id, @s.trigger_event.reload.company_id
    assert_equal @s.target.id, @s.entity_version.reload.company_id
    assert_equal @s.target.id, @s.project_integration.reload.company_id

    assert_equal "Launchpad (2)", report.dig("name", "to")
    assert_equal [ "project_moved_in", "project_moved_out" ],
                 Audit.where(associated: project).order(:action).pluck(:action)
  end

  test "copies the company assets the workflow points at and moves every reference to the copy" do
    move(member_policy: "add")

    copy = Asset.find_by!(scope: @s.project, folder: "handbook", name: "style.md")
    assert_equal "test file content", copy.latest_version.file.read
    assert_equal [ copy.id ], @s.step.reload.asset_ids
    assert_equal "Follow {{asset:#{copy.id}}} closely.", @s.step.instructions
    assert_equal "Check against {{asset:#{copy.id}}}.", @s.sub_step.reload.instructions
    assert_equal [ copy.id ], @s.workflow.reload.base_asset_ids
    assert_equal @s.source.id, @s.company_asset.reload.company_id, "the original stays with its company"
  end

  test "detaches what stays with the source and cancels the run that had not started" do
    report = move(member_policy: "add")

    assert_nil @s.company_repository.reload.integration_id
    assert_equal @s.project_integration, @s.project_repository.reload.integration
    assert_equal "cancelled", @s.pending_run.reload.state
    assert_nil @s.project.reload.session_concurrency_limit, "the target cannot hold the reservation"
    assert_equal [ "northwind/site" ], report["detached_repositories"].pluck("full_name")
    assert_equal [ @s.pending_run.id ], report["cancelled_runs"].pluck("id")
    assert_equal({ "max_sessions" => 2 }, report["dropped_reservation"])
  end

  test "keeps a reservation the target can hold" do
    SessionConcurrencyLimit.set!(scope: @s.target, max_sessions: 5)

    move(member_policy: "add")

    assert_equal 2, @s.project.reload.session_concurrency_limit.max_sessions
    assert_equal @s.target.id, @s.project.session_concurrency_limit.company_id
  end

  test "adding people makes them employees of the target and keeps their work" do
    report = move(member_policy: "add")

    membership = @s.outsider.company_memberships.find_by!(company: @s.target)
    assert_equal [ "employee", "active" ], [ membership.role, membership.state ]
    assert_includes @s.project.reload.collaborators, @s.outsider
    assert_equal @s.outsider, @s.parent_task.reload.assignee
    assert_equal [ @s.outsider.email ], report["added_members"].pluck("email")
    assert_empty report["cleared_assignments"]
  end

  test "dropping people takes them off the project and clears their tasks" do
    report = move(member_policy: "drop")

    assert_not @s.outsider.company_memberships.exists?(company: @s.target)
    assert_not_includes @s.project.reload.collaborators, @s.outsider
    assert_nil @s.parent_task.reload.assignee
    assert_equal @s.shared_member, @s.child_task.reload.assignee
    assert_equal [ @s.parent_task.number ], report["cleared_assignments"].pluck("number")
  end

  test "a new owner takes over and the previous one stays on as a collaborator" do
    move(member_policy: "add", owner: @s.target_admin)

    project = @s.project.reload
    assert_equal @s.target_admin, project.owner
    assert_includes project.collaborators, @s.owner
  end

  test "blocking on missing people refuses the move and changes nothing" do
    error = assert_raises(ProjectMove::Refused) { move(member_policy: "block") }

    assert_match(/#{@s.outsider.email} is not a member of Contoso/, error.message)
    assert_unmoved
  end

  test "refuses while an agent is live in the project" do
    create(:terminal_session, :agent_session, project: @s.project, user: @s.owner, state: "ready")

    error = assert_raises(ProjectMove::Refused) { move(member_policy: "add") }

    assert_match(/1 session\(s\) are running/, error.message)
    assert_unmoved
  end

  test "refuses to cancel work the admin did not confirm" do
    error = assert_raises(ProjectMove::Refused) { move(member_policy: "add", confirm_cancellations: false) }

    assert_match(/cancels 1 run/, error.message)
    assert_equal "pending", @s.pending_run.reload.state
    assert_unmoved
  end

  test "refuses an owner who cannot own a project in the target" do
    assert_raises(ProjectMove::Refused) { move(member_policy: "add", owner: @s.outsider) }

    assert_unmoved
  end

  test "a failure inside the move rolls everything back and removes the asset copies" do
    Audit.stubs(:create!).raises(ActiveRecord::RecordInvalid)

    assert_raises(ActiveRecord::RecordInvalid) { move(member_policy: "add") }

    assert_unmoved
    assert_equal [ @s.company_asset.id ], @s.step.reload.asset_ids
    assert_not Asset.exists?(scope: @s.project, name: "style.md")
  end

  test "detaches a tracker whose integration stays with the source" do
    tracker = ProjectTracker.new(project: @s.project, integration: @s.company_integration, provider: "github",
                                 external_scope_id: "northwind/site", name: "Northwind issues", handle: "nw")
    tracker.save!(validate: false)

    report = move(member_policy: "add")

    assert_equal "detached", tracker.reload.status
    assert_equal [ "Northwind issues" ], report["detached_trackers"].pluck("name")
  end

  test "disconnects a project's Azure DevOps integration, whose installation belongs to the source" do
    ado = create(:integration, :azure_devops, :active, company: @s.source, project: @s.project)

    report = move(member_policy: "add")

    assert_equal [ "inactive", @s.target.id ], [ ado.reload.status, ado.company_id ]
    assert_equal [ ado.id ], report["deactivated_integrations"].pluck("id")
  end

  test "switches the workflows on a runner of the source to Hosted, archived ones included, and lists them" do
    runner = create(:runner, company: @s.source, name: "Prod VPC")
    @s.workflow.update!(runner: runner)
    archived = create(:workflow, scope: @s.project, name: "Hotfix", runner: runner, deleted_at: Time.current)

    report = move(member_policy: "add")

    assert_equal [ nil, @s.target.id ], [ @s.workflow.reload.runner_id, @s.workflow.company_id ]
    assert_equal [ nil, @s.target.id ], [ archived.reload.runner_id, archived.company_id ]
    assert_equal [ [ archived.id, "Hotfix", true, "Prod VPC" ], [ @s.workflow.id, "Release", false, "Prod VPC" ] ],
                 report["workflows_switched_to_hosted"].map { |row| row.values_at("id", "name", "archived", "runner") }
    assert runner.reload.persisted?, "the runner stays with its company"
  end

  test "refuses while the project owns a runner, and changes nothing" do
    create(:runner, company: @s.source, project: @s.project, name: "Lab", deleted_at: Time.current)

    error = assert_raises(ProjectMove::Refused) { move(member_policy: "add") }

    assert_match(/Runner Lab \(deleted\) belongs to this project, and a runner cannot move to another company\./, error.message)
    assert_unmoved
  end

  test "clears the runner of past runs and sessions, which keep their history in the target" do
    runner = create(:runner, company: @s.source)
    @s.completed_run.update_columns(runner_id: runner.id)
    @s.finished_session.update_columns(runner_id: runner.id)

    report = move(member_policy: "add")

    assert_equal [ nil, "completed" ], [ @s.completed_run.reload.runner_id, @s.completed_run.state ]
    assert_equal [ nil, @s.target.id ], [ @s.finished_session.reload.runner_id, @s.finished_session.company_id ]
    assert_equal({ "runs" => 1, "sessions" => 1 }, report["cleared_runner_references"])
    assert runner.reload.persisted?, "the runner stays with its company"
  end

  test "the move drops the source runner from the workflows' versions, and a revert to one restores Hosted" do
    runner = create(:runner, company: @s.source, name: "Prod VPC")
    @s.workflow.update_column(:current_version_number, @s.entity_version.number)
    on_runner = Versions.save!(@s.workflow, actor: Versions::Actor.system) do |workflow|
      workflow.update!(runner: runner, description: "on runner")
    end
    Versions.save!(@s.workflow, actor: Versions::Actor.system) { |workflow| workflow.update!(runner: nil, description: "hosted") }
    move(member_policy: "add")

    workflow = @s.workflow.reload
    assert_empty EntityVersion.where(versionable: workflow).where("snapshot -> 'runner_id' IS NOT NULL"),
                 "no version names a runner of the source company"
    assert_equal "on runner", on_runner.reload.snapshot["description"], "the rest of the version is untouched"

    Versions.revert!(workflow, to: on_runner, actor: Versions::Actor.system)
    assert_equal [ nil, "on runner" ], [ workflow.reload.runner_id, workflow.description ]
  end

  private

  def move(member_policy:, owner: @s.owner, confirm_cancellations: true)
    ProjectMove::Mover.new(project: @s.project, target: @s.target, owner: owner, member_policy: member_policy,
                           confirm_cancellations: confirm_cancellations, actor: @super_admin).call
  end

  def assert_unmoved
    project = @s.project.reload
    assert_equal [ @s.source, "Launchpad" ], [ project.company, project.name ]
    assert_equal @s.source.id, @s.workflow.reload.company_id
    assert_equal @s.company_integration, @s.company_repository.reload.integration
    assert_not Audit.exists?(associated: project)
  end
end
