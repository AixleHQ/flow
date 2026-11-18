# frozen_string_literal: true

module PullRequests
  # What TriggerEngine does differently for an event PullRequests::EventPipeline
  # published: the run's pull-request context, the board task a pull request is
  # about, and one run per pull request at a time
  # (docs/design/pull-request-triggers.md §6).
  #
  # Only events whose source is the pipeline qualify. A generic webhook chooses
  # its own event type and data, and must not reach any of this.
  module TriggerSupport
    DEFAULT_TITLE = "PR {{pull_request.number}}: {{pull_request.title}}"
    SKIP_IN_PROGRESS = "pull_request_run_in_progress"

    module_function

    def event?(event)
      event&.source == EventPipeline::SOURCE && event.data.to_h["pull_request"].is_a?(Hash) &&
        event.data.to_h["repository"].is_a?(Hash)
    end

    def run_context(event)
      return {} unless event?(event)

      data = event.data
      chain = Array(data.dig("origin", "chain"))
      context = {
        "event_type" => event.event_type, "repository" => data["repository"].to_h.slice("id", "full_name", "provider"),
        "actor" => data.dig("actor", "name"), "review" => data["review"].to_h.slice("verdict", "body").presence,
        "comment" => data["comment"].to_h.slice("id", "author", "text", "file", "line", "reply_to").presence,
        "chain" => chain, "depth" => chain.size
      }
      { "pull_request" => data["pull_request"].to_h.slice("number", "title", "url", "source_branch", "target_branch", "author")
                                              .merge(context).compact }
    end

    # Another run of the same trigger for the same pull request while one is
    # still going would work the same branch at the same time; the run in
    # progress reads the pull request's reviews and comments itself. Locks the
    # binding, so two events arriving together agree on which one starts.
    def run_in_progress?(binding, event)
      return false unless binding&.pull_request_event? && event?(event)

      binding.lock!
      TriggerDispatch.joins(:trigger_event, :workflow_run)
                     .where(trigger_binding_id: binding.id, status: "started", trigger_events: { subject: event.subject })
                     .merge(WorkflowRun.active)
                     .exists?
    end

    # The active task in the binding's project this pull request is about: one
    # linked to it by an earlier run of a trigger, else the task whose run opened
    # it. Several candidates is ambiguous, and no task is better than the wrong one.
    def linked_task(binding, event)
      links = links_for(binding, event).to_a
      same_workflow = links.select { |link| link.data["workflow_id"].to_s == binding.workflow_id.to_s }
      return same_workflow.first.board_task if same_workflow.any?
      return links.first.board_task if links.one?

      if links.many?
        Rails.logger.info("[PullRequests::TriggerSupport] ambiguous_external_subject binding #{binding.id} event #{event.id}")
        return nil
      end
      opened_by(binding, event)
    end

    def find_or_create_task(binding, event)
      lock!(binding, event)
      linked_task(binding, event) || yield
    end

    def link!(task, binding, event)
      identity = event.data["external_resource"].to_h
      return if task.nil? || identity["external_id"].blank?

      ExternalResource.find_or_create_by!(
        board_task: task, kind: ExternalResource::PULL_REQUEST, provider: identity["provider"],
        instance: identity["instance"], external_id: identity["external_id"]
      ) do |link|
        link.data = { "key" => identity["key"], "url" => identity["url"], "workflow_id" => binding.workflow_id,
                      "binding_id" => binding.id, "repository_id" => event.data.dig("repository", "id") }.compact
      end
    end

    def task_body(event)
      data = event.data
      pull_request = data["pull_request"].to_h
      what = data["review"] ? "Review (#{data.dig('review', 'verdict').to_s.tr('_', ' ')})" : "Comment"
      by = data.dig("actor", "name").presence
      [
        pull_request["url"] && "Pull request: #{pull_request['url']}",
        data["text"].presence && "#{what}#{" by #{by}" if by}:\n\n#{data['text']}"
      ].compact.join("\n\n").presence
    end

    def links_for(binding, event)
      identity = event.data["external_resource"].to_h
      ExternalResource.identifying(provider: identity["provider"], instance: identity["instance"],
                                   external_id: identity["external_id"], kind: ExternalResource::PULL_REQUEST)
                      .joins(board_task: :board).where(boards: { project_id: binding.project_id })
                      .merge(BoardTask.active).includes(:board_task).order(:created_at, :id)
    end

    def opened_by(binding, event)
      repository_id = event.data.dig("repository", "id")
      number = event.data.dig("pull_request", "number")
      return nil if repository_id.blank? || number.blank?

      run_ids = PullRequestOperation.where(repository_id: repository_id, operation: "create", state: "succeeded",
                                           pull_request_number: number.to_s)
                                    .where.not(workflow_run_id: nil).order(created_at: :desc).pluck(:workflow_run_id)
      BoardTask.active.joins(:board).where(boards: { project_id: binding.project_id })
               .where(id: WorkflowRun.where(id: run_ids).select(:board_task_id)).order(:created_at, :id).first
    end

    def lock!(binding, event)
      identity = event.data["external_resource"].to_h
      key = [ binding.project_id, ExternalResource::PULL_REQUEST, identity["provider"], identity["instance"],
              identity["external_id"] ].join(":")
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", key ])
      )
    end
  end
end
