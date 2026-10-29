# frozen_string_literal: true

module ProjectMove
  # What moving `project` into `target` would do, without doing any of it: what
  # refuses the move, what the move cancels, detaches, copies or renames, and who
  # loses access. The admin reads it before confirming; the Mover reads it again
  # under the project lock and acts on that second reading.
  class Preflight
    # A container is up and an agent may be working in it. The move would pull its
    # credentials, repositories and tenant out from under it, so it waits.
    LIVE_SESSION_STATES = %w[running ready finishing].freeze
    # Nothing has started yet: cancelling loses no work.
    WAITING_SESSION_STATES = %w[not_started queued].freeze

    attr_reader :project, :source, :target

    def initialize(project:, target:)
      @project = project
      @source = project.company
      @target = target
    end

    def blockers
      list = []
      list << "The project already belongs to #{target.name}." if target.id == source.id
      list << "#{target.name} is #{target.state} and cannot take projects." unless target.active?
      if live_sessions.any?
        list << "#{live_sessions.size} session(s) are running in this project. Stop them before moving it."
      end
      list.concat(runner_blockers)
      list
    end

    def movable? = blockers.empty?

    # People who work on the project now: its owner, collaborators and assignees.
    def people
      @people ||= User.where(id: [ project.owner_id, *project.project_collaborators.pluck(:user_id), *assignee_ids ].uniq)
                      .order(:name).to_a
    end

    def missing_members
      @missing_members ||= begin
        member_ids = target.company_memberships.active.pluck(:user_id).to_set
        people.reject { |user| member_ids.include?(user.id) }
      end
    end

    # A missing member whose membership in the target exists but is not active was
    # suspended, revoked or never accepted there; adding them would overrule that.
    def inactive_target_memberships
      @inactive_target_memberships ||=
        target.company_memberships.where(user_id: missing_members.map(&:id)).where.not(state: "active")
              .pluck(:user_id, :state).to_h
    end

    def owner_candidates
      target.ownership_candidates.order(:name)
    end

    def live_sessions
      @live_sessions ||= project.terminal_sessions.where(state: LIVE_SESSION_STATES).order(:id).to_a
    end

    def runs_to_cancel
      @runs_to_cancel ||= project.workflow_runs.active.includes(:workflow).order(:id).to_a
    end

    # Sessions waiting for a slot, or created and never started, that no run above
    # accounts for: someone's interactive session still in the queue.
    def sessions_to_cancel
      @sessions_to_cancel ||= waiting_sessions.where.not(id: StepRun.where(workflow_run_id: runs_to_cancel.map(&:id))
                                                                     .select(:terminal_session_id)).to_a
    end

    def waiting_sessions
      project.terminal_sessions.where(state: WAITING_SESSION_STATES).order(:id)
    end

    def cancellations? = runs_to_cancel.any? || sessions_to_cancel.any?

    # A runner belongs to its company, and its tenant keys hold a project's runners
    # and the runner a workflow names to that company (docs/design/agent-runtimes/
    # DESIGN.md §2, §3.4). Neither can follow the project, so either blocks the
    # move, a deleted runner included: its row stays, for the history that names it.
    def own_runners
      @own_runners ||= Runner.where(project_id: project.id).order(:name).to_a
    end

    # Archived workflows included: the move rewrites their company too.
    def workflows_on_runners
      @workflows_on_runners ||= Workflow.for_project(project).where.not(runner_id: nil)
                                        .includes(runner: :company).order(:name).to_a
    end

    # The runs and sessions that name a runner. They are history (a live session
    # blocks the move, and work that has not started is cancelled), so the move
    # clears their runner_id rather than refuse.
    def runner_history
      {
        "runs" => project.workflow_runs.where.not(runner_id: nil).count,
        "sessions" => project.terminal_sessions.where.not(runner_id: nil).count
      }
    end

    # Repositories cloned through an integration that stays with the source.
    def detached_repositories
      @detached_repositories ||= Repository.where(scope_type: "Project", scope_id: project.id)
                                           .where.not(integration_id: nil)
                                           .where.not(integration_id: project.integrations.select(:id))
                                           .order(:full_name).to_a
    end

    # Trackers on an integration that stays with the source. Trackers::EventPipeline
    # routes by integration alone, so an attached one would keep feeding the source
    # company's tracker into the moved project. Providers only accept a project's
    # own integration today; this is the guard for a row that predates that rule.
    def detached_trackers
      @detached_trackers ||= project.project_trackers.where.not(status: "detached")
                                    .where.not(integration_id: project.integrations.select(:id))
                                    .order(:name).to_a
    end

    # The project's own integrations that move but cannot stay connected, with why.
    def deactivated_integrations
      @deactivated_integrations ||= project.integrations.active.order(:id).filter_map do |integration|
        reason = deactivation_reason(integration)
        [ integration, reason ] if reason
      end
    end

    def chat_bindings
      @chat_bindings ||= TriggerBinding.where(project: project, event_type: Chat::EVENT_TYPE).order(:id).to_a
    end

    # Company assets the project's workflows point at. The target cannot see them,
    # so the project takes a copy of each.
    def company_assets
      @company_assets ||= Asset.where(id: referenced_asset_ids, scope_type: "Company", scope_id: source.id,
                                      deleted_at: nil).order(:folder, :name).to_a
    end

    def name_after = free_value(:name) { |n| "#{project.name} (#{n})" }
    def slug_after = free_value(:slug) { |n| "#{project.slug}-#{n}" }

    def reservation = project.session_concurrency_limit

    def reservation_dropped?
      return false if reservation.nil?

      !SessionConcurrencyAllocation.new(company_id: target.id, excluding: reservation.id).fits?(reservation.max_sessions)
    end

    # People who will have no agent credential in the target, so cannot run an agent
    # there until they sign in again.
    def people_without_agent_credentials
      with_credentials = AgentCredential.where(company_id: target.id, user_id: people.map(&:id)).distinct.pluck(:user_id)
      people.reject { |user| with_credentials.include?(user.id) }
    end

    def to_h
      {
        "source_company" => company_row(source),
        "target_company" => company_row(target),
        "name" => { "from" => project.name, "to" => name_after },
        "slug" => { "from" => project.slug, "to" => slug_after },
        "missing_members" => missing_members.map { |user| user_row(user) },
        **cancellation_report,
        "detached_repositories" => detached_repositories.map { |repo| { "id" => repo.id, "full_name" => repo.full_name } },
        "detached_trackers" => detached_trackers.map { |tracker| { "id" => tracker.id, "name" => tracker.name } },
        "deactivated_integrations" => deactivated_integrations.map do |integration, reason|
          { "id" => integration.id, "name" => integration.name, "provider" => integration.provider.to_s, "reason" => reason }
        end,
        "chat_triggers" => chat_bindings.map { |binding| { "id" => binding.id, "name" => binding.name } },
        "copied_assets" => company_assets.map { |asset| { "id" => asset.id, "path" => asset_path(asset) } },
        "dropped_reservation" => reservation_dropped? ? { "max_sessions" => reservation.max_sessions } : nil,
        "cleared_runner_references" => runner_history,
        "without_agent_credentials" => people_without_agent_credentials.map { |user| user_row(user) }
      }
    end

    def cancellation_report
      {
        "cancelled_runs" => runs_to_cancel.map { |run| { "id" => run.id, "workflow" => run.workflow&.name, "state" => run.state } },
        "cancelled_sessions" => sessions_to_cancel.map { |session| { "id" => session.id, "state" => session.state } }
      }
    end

    private

    def runner_blockers
      list = []
      if own_runners.any?
        list << "#{own_runners.map { |runner| runner_label(runner) }.to_sentence} belong#{'s' if own_runners.one?} " \
                "to this project, and a runner cannot move to another company."
      end
      workflows_on_runners.group_by(&:runner).each do |runner, workflows|
        names = workflows.map { |workflow| workflow.archived? ? "#{workflow.name} (archived)" : workflow.name }
        list << "#{workflows.one? ? 'Workflow' : 'Workflows'} #{names.to_sentence} " \
                "run#{'s' if workflows.one?} on runner #{runner.name} of #{runner.company.name}. " \
                "Switch #{workflows.one? ? 'it' : 'them'} to Hosted before moving."
      end
      list
    end

    def runner_label(runner) = runner.deleted? ? "Runner #{runner.name} (deleted)" : "Runner #{runner.name}"

    def assignee_ids
      BoardTask.joins(:board).where(boards: { project_id: project.id }).where.not(assignee_id: nil).distinct.pluck(:assignee_id)
    end

    def deactivation_reason(integration)
      if integration.azure_devops_installation_id.present?
        "Its Azure DevOps installation, and the tenant consent behind it, belong to #{source.name}."
      elsif github_installation_held_elsewhere?(integration)
        "Its GitHub installation is also connected to #{source.name}, and one installation serves one company."
      end
    end

    def github_installation_held_elsewhere?(integration)
      return false unless integration.provider.to_s == "github" && integration.github_installation_id.present?
      return false if Github::InstallationOwnership.enforced?

      Integration.where(provider: "github", github_installation_id: integration.github_installation_id, status: "active")
                 .where.not(id: integration.id).where.not(company_id: target.id).exists?
    end

    def referenced_asset_ids
      steps = Step.unscoped.where(workflow_id: workflow_ids)
      ids = steps.pluck(:asset_ids, :instructions).flat_map do |asset_ids, instructions|
        Array(asset_ids).map(&:to_i) + InstructionReferences.ids(instructions, "asset")
      end
      ids += SubStep.where(step_id: steps.select(:id)).pluck(:instructions).flat_map { |text| InstructionReferences.ids(text, "asset") }
      ids += Workflow.where(id: workflow_ids).map(&:base_asset_ids).flatten.map(&:to_i)
      ids.uniq
    end

    def workflow_ids
      @workflow_ids ||= Workflow.where(scope_type: "Project", scope_id: project.id).pluck(:id)
    end

    def free_value(attribute)
      taken = target.projects.where.not(id: project.id).pluck(attribute).to_set
      value = project.public_send(attribute)
      suffix = 1
      value = yield(suffix += 1) while taken.include?(value)
      value
    end

    def company_row(company) = { "id" => company.id, "name" => company.name }
    def user_row(user) = { "id" => user.id, "name" => user.name, "email" => user.email }

    def asset_path(asset) = [ asset.folder.presence, asset.name ].compact.join("/")
  end
end
