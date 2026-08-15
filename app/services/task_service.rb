# frozen_string_literal: true

class TaskService
  class << self
    def create(board:, params:, actor:)
      task = board.board_tasks.build(params)

      pending_event = nil
      saved = false
      ActiveRecord::Base.transaction do
        saved = task.save
        raise ActiveRecord::Rollback unless saved
        # Record the auto-trigger event atomically with the task so a crash can't
        # leave the task created but the trigger lost (it is dispatched below).
        pending_event = record_pending_auto_trigger(task: task, column: task.board_column, actor: actor)
      end
      return task unless saved

      record_activity(board, :task_created, actor, task: task,
        metadata: { title: task.title, task_type: task.task_type })
      TriggerEngine.dispatch_pending(pending_event) if pending_event

      task
    end

    # A column change is a MOVE, not an attribute write. It has to record a
    # ColumnTransition, log task_moved, and fire the column's auto-trigger — and
    # `board_column_id` is a permitted attribute on the task endpoint, so without
    # routing it through #move an ordinary PATCH relocates the card while
    # silently skipping all three. Everything else still saves in one write, so
    # a request that renames a task AND moves it produces one task_updated for
    # the rename and one task_moved for the move.
    def update(task:, params:, actor:)
      attrs = (params.respond_to?(:to_unsafe_h) ? params.to_h : params).with_indifferent_access
      to_column = extract_move_target(task, attrs)

      task.assign_attributes(attrs)
      changes = task.changes.except("updated_at")

      return task unless task.save

      record_activity(task.board, :task_updated, actor, task: task, metadata: { changes: changes }) if changes.any?
      return task if to_column.nil?

      move(task: task, to_column: to_column, actor: actor)
    end

    def archive(task:, actor:)
      return task if task.archived?

      if task.update(archived_at: Time.current)
        record_activity(task.board, :task_archived, actor, task: task, metadata: { title: task.title })
      end

      task
    end

    def unarchive(task:, actor:)
      return task unless task.archived?

      if task.update(archived_at: nil)
        record_activity(task.board, :task_unarchived, actor, task: task, metadata: { title: task.title })
      end

      task
    end

    def destroy(task:, actor:)
      title = task.title
      board = task.board

      if task.destroy
        record_activity(board, :task_deleted, actor, metadata: { title: title })
      end

      task
    end

    def move(task:, to_column:, position: nil, actor:, actor_type: :human)
      from_column = task.board_column
      column_changed = from_column.id != to_column.id

      pending_event = nil
      ActiveRecord::Base.transaction do
        task.lock!

        if position
          if column_changed
            insert_at_position(to_column, task, position)
          else
            reorder_within_column(to_column, task, task.position, position)
          end
        end

        new_pos = position || (to_column.board_tasks.maximum(:position).to_i + 1)
        task.update!(board_column: to_column, position: new_pos)

        # Record the auto-trigger event atomically with the move; it is dispatched
        # inline below (and recovered by the relay if this process then dies).
        pending_event = record_pending_auto_trigger(task: task, column: to_column, actor: actor) if column_changed
      end

      if column_changed
        ColumnTransition.create!(
          board_task: task, from_column: from_column, to_column: to_column,
          actor: actor, actor_type: actor_type
        )
        record_activity(task.board, :task_moved, actor, task: task,
          metadata: { from_column: from_column.name, to_column: to_column.name })
        TriggerEngine.dispatch_pending(pending_event) if pending_event
      end

      task.reload
    end

    def add_comment(task:, params:, actor:)
      comment = task.task_comments.build(params)
      comment.author = actor
      comment.author_type = :human

      if comment.save
        record_activity(task.board, :comment_added, actor, task: task,
          metadata: { tag: comment.tags&.first, preview: comment.body.to_s.truncate(100) })
      end

      comment
    end

    def add_asset(task:, params:, actor:)
      asset = task.task_assets.build(params)
      asset.author = actor
      asset.author_type = :human

      if asset.save
        record_activity(task.board, :asset_attached, actor, task: task,
          metadata: { name: asset.name, content_type: asset.file&.metadata&.dig("mime_type") })
      end

      asset
    end

    def destroy_asset(task:, asset:, actor:)
      asset.destroy
    end

    def trigger_workflow(task:, binding:, actor:)
      unless [ :manual, :auto ].include?(binding&.trigger_mode&.to_sym)
        return { error: "No workflow binding on current column" }
      end

      if task.workflow_runs.where(state: %w[pending running paused]).exists?
        return { error: "Active workflow run already exists for this task" }
      end

      event = TriggerEngine.record_event(
        event_type: TriggerEngine::MANUAL_EVENT_TYPE,
        source: "manual",
        subject: task.id,
        data: { "workflow_id" => binding.workflow_id, "column_id" => task.board_column_id,
                "requested_by_id" => actor&.id },
        project: task.board.project,
        board_task: task,
        actor: run_owner_for(task, requested_by: actor),
        relay_state: "pending"
      )

      run = TriggerEngine.dispatch_pending(event).first
      run || { error: "Workflow could not be started" }
    end

    # Returns true if THIS call performed the transition, false if the gate was
    # already terminal (see with_pending_gate).
    def resolve_gate(gate:, resolution_data: {})
      pending_event = nil

      transitioned = with_pending_gate(gate) do
        gate.update!(
          status: :resolved,
          resolved_at: Time.current,
          resolution_data: resolution_data
        )
        task = gate.board_task
        pending_event = record_pending_auto_trigger(task: task, column: task.board_column, actor: gate.creator)
      end

      TriggerEngine.dispatch_pending(pending_event) if pending_event
      transitioned
    end

    # Resolve a gate from a reconciliation probe rather than from its webhook.
    # Identical to resolve_gate — same transition, same auto-trigger — plus a
    # board activity, because a gate that resolved without its webhook is exactly
    # the case an operator needs to be able to see after the fact.
    #
    # Returns false without recording anything when the gate reached a terminal
    # state while the provider was being probed: the winner already recorded its
    # own outcome, and a second activity row would claim this sweep did the work.
    def resolve_gate_by_reconciliation(gate:, resolution_data:)
      task = gate.board_task
      return false unless resolve_gate(gate: gate, resolution_data: resolution_data)

      record_activity(task.board, :gate_reconciled, gate.creator, task: task, actor_type: :system,
        metadata: { gate_id: gate.id, gate_type: gate.gate_type.to_s,
                    conclusion: gate.reload.conclusion, source: gate.source })
      true
    end

    # End a gate's wait without a provider verdict: nothing can resolve it (its
    # run/repository is unreadable) or its TTL ran out while CI was still going.
    #
    # A stale gate stops blocking the column auto-trigger — leaving it pending is
    # what wedged tasks forever — but it is never recorded as a pass. The reason
    # goes on the gate (`diagnostic_reason`, surfaced on the card), into its
    # resolution_data as `outcome: "stale"`, and onto the board activity feed, so
    # the bypass is documented rather than silent.
    #
    # Returns true if THIS call staled the gate, false if it was already terminal —
    # a provider verdict that landed while we were probing MUST NOT be overwritten
    # by "we do not know".
    def mark_gate_stale(gate:, reason:, detail: nil, now: Time.current)
      task = gate.board_task
      pending_event = nil

      transitioned = with_pending_gate(gate) do
        gate.update!(
          status: :stale,
          diagnostic_reason: reason,
          resolution_data: gate.resolution_data.merge({
            "outcome" => "stale",
            "reason" => reason,
            "detail" => detail,
            "source" => "reconciliation",
            "stale_at" => now.utc.iso8601
          }.compact)
        )
        pending_event = record_pending_auto_trigger(task: task, column: task.board_column, actor: gate.creator)
      end

      return false unless transitioned

      record_activity(task.board, :gate_stale, gate.creator, task: task, actor_type: :system,
        metadata: { gate_id: gate.id, gate_type: gate.gate_type.to_s,
                    reason: reason, detail: detail, source: gate.source })

      TriggerEngine.dispatch_pending(pending_event) if pending_event
      true
    end

    # Delete a gate, re-evaluating the column auto-trigger ONLY when the gate was
    # still pending.
    #
    # A terminal gate (`resolved` or `stale`) already stopped blocking the column
    # and had its auto-trigger evaluated and dispatched at transition time. The
    # row that stays behind is an audit record, so deleting it releases nothing —
    # re-evaluating here would dispatch the same column workflow a second time
    # (record_pending_auto_trigger does not guard against an already-active run).
    #
    # The status is re-read under the row lock, the same compare-and-set idiom as
    # with_pending_gate: a webhook or the reconciliation sweep can take the gate
    # terminal between load and delete, and that writer dispatches the trigger.
    def remove_gate(gate:, actor:)
      task = gate.board_task
      column = task.board_column

      pending_event = nil
      ActiveRecord::Base.transaction do
        was_pending = gate.lock!.pending?
        gate.destroy!
        pending_event = record_pending_auto_trigger(task: task, column: column, actor: actor) if was_pending
      end

      TriggerEngine.dispatch_pending(pending_event) if pending_event
    end

    # Record a pending column-trigger event and dispatch it inline. A convenience
    # wrapper around the in-transaction outbox path for callers that auto-trigger
    # outside a domain transaction (and for tests). Returns the WorkflowRun or nil.
    def check_auto_trigger(task:, column:, actor:)
      event = record_pending_auto_trigger(task: task, column: column, actor: actor)
      TriggerEngine.dispatch_pending(event).first if event
    rescue StandardError => e
      Rails.logger.error("[TaskService] Auto-trigger failed: #{e.message}")
      nil
    end

    # Apply the auto-trigger guards and, if they pass, record a pending
    # column-trigger event (the transactional-outbox row). Returns the recorded
    # TriggerEvent or nil. MUST be called inside the producer's transaction so the
    # event commits atomically with the domain write; the caller dispatches it
    # after the transaction commits (and OutboxRelay recovers it on a crash).
    #
    # No rescue here on purpose: a failure to record must roll the whole
    # transaction back (atomic-or-nothing), not silently drop the trigger while
    # committing the domain write. The out-of-transaction check_auto_trigger
    # wrapper above is where best-effort error handling lives.
    def record_pending_auto_trigger(task:, column:, actor:)
      binding = column.column_workflow_binding
      return nil unless binding&.trigger_mode&.to_sym == :auto
      return nil if task.gates.pending.exists?
      return nil if quota_block_auto_trigger?(binding, column)

      TriggerEngine.record_column_trigger(
        binding: binding, task: task,
        actor: run_owner_for(task, requested_by: actor), requested_by: actor
      )
    end

    private

    # Pulls `board_column_id` out of an update's attributes when it names a
    # DIFFERENT column on this task's board — that is a move, and #update hands
    # it to #move once the rest of the write has landed. Anything else (blank,
    # the column the task is already in, or a column belonging to another board)
    # is left in the attributes, so the model's own `column_belongs_to_board`
    # validation still rejects a foreign column instead of it being dropped here.
    def extract_move_target(task, attrs)
      column_id = attrs[:board_column_id]
      return nil if column_id.blank? || column_id.to_i == task.board_column_id

      column = task.board.board_columns.find_by(id: column_id)
      attrs.delete(:board_column_id) if column
      column
    end

    # Compare-and-set for a gate's one-way `pending` → terminal transition. Takes a
    # row lock, RE-READS the status inside it, and yields only while the gate is
    # still pending; the block therefore runs at most once across every writer.
    # Same idiom as TriggerEngine#fire_workflow's `dispatch.with_lock`.
    #
    # Three writers race for a CI gate: its webhook delivery, the reconciliation
    # sweep, and a second sweeper (Temporal retries an activity, `overlap: skip`
    # only bounds the schedule). Without this, a webhook's `failure` could be
    # overwritten by the sweep's `stale` at TTL, and each redundant winner would
    # emit its own activity row and dispatch the column auto-trigger again.
    #
    # `with_lock` opens the transaction, so the caller's domain write and the
    # auto-trigger outbox row it records still commit atomically. Returns whether
    # the block ran; a gate deleted from under us counts as lost, not as an error.
    def with_pending_gate(gate)
      gate.with_lock do
        next false unless gate.pending?

        yield
        true
      end
    rescue ActiveRecord::RecordNotFound
      false
    end


    # WHO a launched run belongs to — which is not the same question as who was
    # allowed to launch it.
    #
    # `run.user` is what the run SPENDS: SessionService.create_for_workflow_step
    # reads it to choose the agent credential, the agent runtime and the model,
    # so it decides which account executes the work and which one is billed. The
    # work on a card belongs to the person the card is assigned to, so that is
    # who owns its runs.
    #
    # Which is why the person who ACTED is the wrong answer even when there is
    # one: whoever pressed Run, or dragged the card into an automated column, may
    # simply have been tidying the board. Moving somebody else's card is an act of
    # housekeeping; the work it kicks off is still theirs.
    #
    # This also has to hold because the agent side already assumes it: every
    # session tool resolves its own actor as `task.assignee || workflow_run&.user`
    # (InternalTools::BoardMoveTask and friends), where `workflow_run` is the run
    # of the session doing the work. A run owned by the wrong account therefore
    # has an agent that moves every unassigned card as that account, firing more
    # runs owned by it, whose agents do the same — so one wrong owner does not
    # stay one wrong run, it walks the board. Resolving ownership in ONE place is
    # what keeps every entry point (the card's Run button, the personal MCP tool,
    # a column auto-trigger) from having to get it right separately.
    #
    # `requested_by` remains the fallback for an unassigned card, and every
    # caller records it in the event's data, so "who asked" is never lost.
    def run_owner_for(task, requested_by:)
      assignee = task.assignee
      assignee && can_own_runs?(assignee, task) ? assignee : requested_by
    end

    # Can this account actually carry a run here? Three ways it cannot:
    #
    #   - no active membership in the task's company — it is not theirs to run;
    #   - the viewer role — the platform refuses to let a viewer launch a session
    #     at all, so attributing a run to one smuggles in work they could not
    #     have started themselves;
    #   - no agent credential in that company — and this one is the reason the
    #     check exists rather than trusting the assignee blindly. A nil
    #     credential is not an error anywhere downstream: SessionContextService
    #     writes credentials only `if credential.present?`, so the container
    #     comes up with nothing to authenticate as and the step dies with
    #     whatever the CLI says about being logged out. Handing a run to someone
    #     who never connected an agent would trade a wrong-account run for a
    #     silently broken one.
    #
    # Note the residual case this does NOT cover: a candidate who holds some
    # credential but not the runtime the step pins (`required_agent_runtime`)
    # still lands on a nil credential. That is pre-existing — it bites any run
    # whose owner lacks the pinned runtime — and resolving it here would mean a
    # second copy of SessionService's runtime cascade.
    def can_own_runs?(candidate, task)
      company_id = task.board&.project&.company_id
      return false if company_id.blank?

      membership = candidate.company_memberships.active.find_by(company_id: company_id)
      return false if membership.nil? || membership.viewer?

      AgentCredential.exists?(user_id: candidate.id, company_id: company_id)
    end

    def record_activity(board, event_type, actor, task: nil, metadata: {}, actor_type: :human)
      BoardActivity.create!(
        board: board, board_task: task, event_type: event_type,
        actor: actor, actor_type: actor_type, metadata: metadata
      )
      board.touch
    rescue StandardError => e
      Rails.logger.warn("[TaskService] Failed to record activity #{event_type}: #{e.message}")
    end

    def insert_at_position(target_column, task, position)
      target_column.board_tasks
        .where.not(id: task.id)
        .where("position >= ?", position)
        .update_all("position = position + 1")
    end

    def reorder_within_column(target_column, task, old_pos, new_pos)
      if old_pos < new_pos
        target_column.board_tasks
          .where.not(id: task.id)
          .where("position > ? AND position <= ?", old_pos, new_pos)
          .update_all("position = position - 1")
      elsif old_pos > new_pos
        target_column.board_tasks
          .where.not(id: task.id)
          .where("position >= ? AND position < ?", new_pos, old_pos)
          .update_all("position = position + 1")
      end
    end

    def quota_block_auto_trigger?(binding, column)
      last_run = binding.workflow.runs
        .where(project: column.board.project)
        .order(created_at: :desc)
        .first
      last_run&.failure_reason == "quota_exceeded"
    end
  end
end
