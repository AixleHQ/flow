# frozen_string_literal: true

module ProjectMove
  # Moves a project into another company of the same deployment. Rows are not
  # copied: their tenant columns change in one transaction, so every id, task
  # number, Temporal schedule id and webhook slug stays what it was.
  #
  # Before the transaction it cancels the work that has not started and copies the
  # company assets the project points at. Inside it, under the project's row lock,
  # it reads the preflight again and refuses if anything changed: a run or session
  # created in the meantime waits on that lock (their foreign key to the project
  # takes a share lock on its row), so whatever the second reading finds is all
  # there is.
  class Mover
    # Rows that carry project_id/company_id beside a scope pair, under the composite
    # key fk_<table>_project_company. That key cannot follow the project's company
    # from one value to another in either order, so these rows have both columns
    # cleared, the project moves, and the columns are derived again from the pair.
    # That leans on each <table>_tenant_columns check still admitting a row with
    # neither column (AddTenantColumnsToScopedResources); a stricter check needs
    # these keys made DEFERRABLE instead.
    SCOPED = [ Agent, Asset, ConfigItem, Folder, MCPServer, Repository, SessionConcurrencyLimit, Skill, Tool, Workflow ].freeze
    # Rows that carry both columns with nothing tying them together.
    DENORMALIZED = [ Integration, TerminalSession, TriggerEvent, EntityVersion, WebhookEndpoint, YoutrackPairing ].freeze

    def initialize(project:, target:, owner:, member_policy:, confirm_cancellations:, actor:, request: nil)
      @project = project
      @source = project.company
      @target = target
      @owner = owner
      @member_policy = member_policy.to_s
      @confirm_cancellations = ActiveModel::Type::Boolean.new.cast(confirm_cancellations)
      @actor = actor
      @request = request
    end

    def call
      preflight = Preflight.new(project: @project, target: @target)
      refuse_unless_allowed!(preflight)
      cancel_waiting_work!(preflight)
      copier = AssetCopier.new(project: @project, assets: preflight.company_assets, source: @source).copy!

      begin
        Project.transaction { move!(preflight, copier) }
      rescue StandardError
        copier.discard!
        raise
      end
    end

    private

    def refuse_unless_allowed!(preflight)
      refuse!(preflight.blockers.join(" ")) unless preflight.movable?
      refuse!("Unknown member policy #{@member_policy.inspect}.") unless @member_policy.in?(MEMBER_POLICIES)
      unless @owner && preflight.owner_candidates.exists?(id: @owner.id)
        refuse!("The new owner must be an active employee or admin of #{@target.name}.")
      end
      if @member_policy == "block" && preflight.missing_members.any?
        refuse!("#{preflight.missing_members.map(&:email).to_sentence} #{preflight.missing_members.one? ? 'is' : 'are'} " \
                "not a member of #{@target.name}. Choose to add or drop them.")
      end
      return if !preflight.cancellations? || @confirm_cancellations

      refuse!("Confirm that the move cancels #{preflight.runs_to_cancel.size} run(s) and " \
              "#{preflight.sessions_to_cancel.size} queued session(s).")
    end

    def cancel_waiting_work!(preflight)
      preflight.runs_to_cancel.each { |run| WorkflowService.cancel(run: run) }
      # A session with no admission yet is not something the admission service
      # cancels; it has to be closed here.
      preflight.waiting_sessions.find_each do |session|
        SessionService.cancel(session: session)
        session.reload
        session.cancel! if session.state.in?(Preflight::WAITING_SESSION_STATES) && session.may_cancel?
      end
    end

    def move!(first_reading, copier)
      @project.lock!
      preflight = Preflight.new(project: @project, target: @target)
      refuse!(preflight.blockers.join(" ")) unless preflight.movable?
      refuse!("A run or session started in #{@project.name} while it was being moved. Try again.") if preflight.cancellations?

      report = preflight.to_h.merge(first_reading.cancellation_report)
      report["copied_assets"] = report["copied_assets"].map { |row| row.merge("copy_id" => copier.copies[row["id"]]&.id) }
      previous_owner_id = @project.owner_id

      copier.rewrite_references!
      detach_links!(preflight)
      clear_runner_references!
      preflight.reservation&.destroy! if preflight.reservation_dropped?
      reparent!(preflight)
      report.merge!(resolve_people!(preflight, previous_owner_id))
      verify_tenant_columns!
      audit!(report)
      report
    end

    def detach_links!(preflight)
      Repository.where(id: preflight.detached_repositories.map(&:id)).update_all(integration_id: nil, updated_at: Time.current)
      ProjectTracker.where(id: preflight.detached_trackers.map(&:id))
                    .update_all(status: "detached", primary: false, updated_at: Time.current)
      Integration.where(id: preflight.deactivated_integrations.map(&:first).map(&:id))
                 .update_all(status: "inactive", updated_at: Time.current)
      # A channel is connected to the old company, not to the project, and so is
      # every code asked for to connect one.
      TriggerBinding.release_chat_channels!(TriggerBinding.where(project_id: @project.id))
      ChatConnectCode.where(project_id: @project.id).delete_all
    end

    # Every runner the project's rows name is one of the source company's, and
    # fk_workflows_runner_company and fk_terminal_sessions_runner_company would
    # hold the rows to it, so this runs before reparent!. The workflows, archived
    # ones included, switch to Hosted (Preflight lists them). Past runs and
    # sessions are history, none of it live (Preflight), and keep it without the
    # runner. Like the asset rewrite, this writes no workflow version: a version
    # from before the move still names the runner, and a revert to it is refused.
    def clear_runner_references!
      now = Time.current
      Workflow.for_project(@project).where.not(runner_id: nil).update_all(runner_id: nil, updated_at: now)
      WorkflowRun.where(project_id: @project.id).where.not(runner_id: nil).update_all(runner_id: nil, updated_at: now)
      TerminalSession.where(project_id: @project.id).where.not(runner_id: nil).update_all(runner_id: nil, updated_at: now)
    end

    def reparent!(preflight)
      SCOPED.each { |model| model.where(project_id: @project.id).update_all(project_id: nil, company_id: nil) }
      @project.update_columns(company_id: @target.id, owner_id: @owner.id, name: preflight.name_after,
                              slug: preflight.slug_after, updated_at: Time.current)
      # Before the repositories: fk_repositories_integration_company holds a
      # repository's integration to the repository's company.
      DENORMALIZED.each { |model| model.where(project_id: @project.id).update_all(company_id: @target.id) }
      SCOPED.each do |model|
        model.where(scope_type: "Project", scope_id: @project.id).update_all(project_id: @project.id, company_id: @target.id)
      end
      @project.reload
    end

    def resolve_people!(preflight, previous_owner_id)
      missing = preflight.missing_members
      added = []
      if @member_policy == "add"
        missing.each do |user|
          next if preflight.inactive_target_memberships.key?(user.id)

          user.company_memberships.create!(company: @target, role: "employee", state: "active", accepted_at: Time.current)
          added << user
        end
      end
      dropped = missing - added

      @project.project_collaborators.where(user_id: [ @owner.id, *dropped.map(&:id) ]).delete_all
      previous_owner = preflight.people.find { |user| user.id == previous_owner_id }
      @project.add_collaborator(previous_owner) if previous_owner && previous_owner != @owner && dropped.exclude?(previous_owner)
      cleared = settle_assignees!(dropped)

      {
        "owner" => { "from" => previous_owner_id, "to" => @owner.id },
        "member_policy" => @member_policy,
        "added_members" => added.map { |user| { "id" => user.id, "email" => user.email } },
        "dropped_members" => dropped.map { |user| { "id" => user.id, "email" => user.email } },
        "cleared_assignments" => cleared
      }
    end

    # An assignee who stays a member of the project's new company keeps the task and
    # becomes a collaborator if that is what it takes to see it; anyone else's
    # assignment is cleared rather than left pointing at someone without access.
    def settle_assignees!(dropped)
      tasks = BoardTask.joins(:board).where(boards: { project_id: @project.id }).where.not(assignee_id: nil)
      cleared = tasks.where(assignee_id: dropped.map(&:id))
      rows = cleared.pluck(:id, :number, :assignee_id).map { |id, number, user_id| { "task_id" => id, "number" => number, "user_id" => user_id } }
      BoardTask.where(id: cleared.select(:id)).update_all(assignee_id: nil, updated_at: Time.current)

      User.where(id: tasks.distinct.pluck(:assignee_id)).find_each do |user|
        @project.add_collaborator(user) unless @project.accessible_by?(user)
      end
      rows
    end

    def verify_tenant_columns!
      stale = (SCOPED + DENORMALIZED).select do |model|
        model.where(project_id: @project.id).where.not(company_id: @target.id).exists?
      end
      raise "#{@project.name} still has #{stale.map(&:table_name).to_sentence} rows in another company" if stale.any?
    end

    def audit!(report)
      [ [ @source, "project_moved_out" ], [ @target, "project_moved_in" ] ].each do |company, action|
        Audit.create!(auditable: company, associated: @project, action: action, user: @actor, audited_changes: report,
                      comment: "#{@actor&.email} moved project #{@project.id} from #{@source.name} to #{@target.name}",
                      remote_address: @request&.remote_ip, request_uuid: @request&.uuid)
      end
    end

    def refuse!(message) = raise(Refused, message)
  end
end
