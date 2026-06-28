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

    def update(task:, params:, actor:)
      task.assign_attributes(params)
      changes = task.changes

      if task.save
        record_activity(task.board, :task_updated, actor, task: task,
          metadata: { changes: changes.except("updated_at") })
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
        data: { "workflow_id" => binding.workflow_id, "column_id" => task.board_column_id },
        project: task.board.project,
        board_task: task,
        actor: actor,
        relay_state: "pending"
      )

      run = TriggerEngine.dispatch_pending(event).first
      run || { error: "Workflow could not be started" }
    end

    def resolve_gate(gate:, resolution_data: {})
      pending_event = nil
      ActiveRecord::Base.transaction do
        gate.update!(
          status: :resolved,
          resolved_at: Time.current,
          resolution_data: resolution_data
        )
        task = gate.board_task
        pending_event = record_pending_auto_trigger(task: task, column: task.board_column, actor: gate.creator)
      end

      TriggerEngine.dispatch_pending(pending_event) if pending_event
    end

    def remove_gate(gate:, actor:)
      task = gate.board_task
      column = task.board_column

      pending_event = nil
      ActiveRecord::Base.transaction do
        gate.destroy!
        pending_event = record_pending_auto_trigger(task: task, column: column, actor: actor)
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

      TriggerEngine.record_column_trigger(binding: binding, task: task, actor: actor)
    end

    private

    def record_activity(board, event_type, actor, task: nil, metadata: {})
      BoardActivity.create!(
        board: board, board_task: task, event_type: event_type,
        actor: actor, actor_type: :human, metadata: metadata
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
