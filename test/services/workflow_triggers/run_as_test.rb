# frozen_string_literal: true

require "test_helper"

class WorkflowTriggers::RunAsTest < ActiveSupport::TestCase
  setup do
    @owner = create(:user, :with_company)
    @company = @owner.companies.first
    @project = create(:project, company: @company, owner: @owner)
    @workflow = create(:workflow, scope: @project)
    @binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner,
                                        event_type: "webhook.deploy")
    @member = create(:user, company: @company)
    @project.add_collaborator(@member)
    create(:agent_credential, user: @member, company: @company)
  end

  def change_to(user, actor: @owner)
    WorkflowTriggers::RunAs.save!(@binding, actor: actor, user_id: user.id) { @binding.save! }
  end

  test "pointing a trigger at another member makes their runs its runs and records who changed it" do
    assert_difference -> { Audit.where(action: WorkflowTriggers::RunAs::AUDIT_ACTION).count }, 1 do
      change_to(@member)
    end

    assert_equal @member, @binding.reload.created_by
    audit = Audit.where(auditable: @binding).sole
    assert_equal @owner, audit.user
    assert_equal @project, audit.associated
    assert_equal({ "created_by_id" => [ @owner.id, @member.id ] }, audit.audited_changes)
    assert_match(/from #{@owner.name} to #{@member.name}/, audit.comment)
  end

  test "a save that leaves the run-as alone records nothing" do
    assert_no_difference -> { Audit.count } do
      WorkflowTriggers::RunAs.save!(@binding, actor: @owner, user_id: @owner.id) { @binding.update!(name: "Renamed") }
    end
  end

  test "refuses someone who can't carry the trigger's runs, and leaves the trigger and the audit trail as they were" do
    outsider = create(:user, company: @company)
    viewer = create(:user, :viewer, company: @company, email: "client-#{SecureRandom.hex(3)}@external.com")
    @project.add_collaborator(viewer)
    create(:agent_credential, user: viewer, company: @company)
    no_agent = create(:user, company: @company)
    @project.add_collaborator(no_agent)

    { outsider => /must be a member of this project/, viewer => /is a viewer/,
      no_agent => /has no agent connected/ }.each do |user, message|
      error = assert_raises(ActiveRecord::RecordInvalid) { change_to(user) }
      assert_match(message, error.message)
      assert_equal @owner, @binding.reload.created_by
    end
    assert_equal 0, Audit.where(auditable: @binding).count
  end

  test "a creator who has since left the project does not block other edits of the trigger" do
    @binding.update_column(:created_by_id, create(:user).id)

    assert @binding.reload.update(name: "Still editable"), @binding.errors.full_messages.to_sentence
  end

  test "candidates are the project's non-viewer members, flagged by whether they have an agent" do
    viewer = create(:user, :viewer, company: @company, email: "client-#{SecureRandom.hex(3)}@external.com")
    @project.add_collaborator(viewer)

    members = WorkflowTriggers::RunAs.candidates(@project)

    assert_equal [ [ @owner.id, false ], [ @member.id, true ] ], members.map { |m| m.values_at(:id, :agent_connected) }
  end
end
