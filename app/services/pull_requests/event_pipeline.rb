# frozen_string_literal: true

module PullRequests
  # One pull-request event → pull_request.* trigger events, published into each
  # Aixle project that has the repository attached and a trigger waiting for it
  # (docs/design/pull-request-triggers.md §5).
  #
  # A review or comment Aixle wrote is attributed to the run that wrote it, through
  # the pull_request_* tools' ledger, or recognized by the connection's own
  # account. Triggers ignore those by default, and the hard limits stop a chain
  # of them whatever the triggers say.
  class EventPipeline
    REVIEW_SUBMITTED = "pull_request.review.submitted"
    COMMENT_CREATED = "pull_request.comment.created"
    EVENT_TYPES = [ REVIEW_SUBMITTED, COMMENT_CREATED ].freeze
    SOURCE = "pull_request"
    VERDICTS = %w[approved changes_requested commented].freeze
    # The ledger's own words for a review (PullRequests::Review).
    LEDGER_VERDICTS = { "approve" => "approved", "request_changes" => "changes_requested" }.freeze
    TEXT_LIMIT = 2_000
    MAX_CHAIN_DEPTH = 5
    PULL_REQUEST_BUDGET = 10
    ATTRIBUTION_WINDOW = 10.minutes

    def self.process(event, repositories) = new.process(event, repositories)

    # The repositories among `repositories` a pull-request trigger (of
    # `event_types`) waits on: one bound to that repository, or to none, in the
    # repository's project.
    def self.awaited(repositories, event_types: EVENT_TYPES)
      repositories = Array(repositories)
      return [] if repositories.empty?

      waiting = TriggerBinding.active.where(event_type: event_types, project_id: repositories.map(&:scope_id).uniq)
                              .distinct.pluck(:project_id, :repository_id)
      repositories.select do |repository|
        waiting.any? { |project_id, bound| project_id == repository.scope_id && (bound.nil? || bound == repository.id) }
      end
    end

    def process(event, repositories)
      return [] if event.review? && VERDICTS.exclude?(event.verdict.to_s)

      self.class.awaited(repositories).filter_map { |repository| publish(repository, event) }
    end

    def self.subject(repository, number)
      "#{repository.integration&.provider}:#{repository_key(repository)}##{number}"
    end

    # What names the repository on its host whichever Aixle project attached it.
    def self.repository_key(repository)
      repository.external_id.presence || repository.full_name.to_s.downcase
    end

    private

    def publish(repository, event)
      origin = origin_for(repository, event)
      return if origin && over_limits?(repository, event, origin)

      event_type = event.review? ? REVIEW_SUBMITTED : COMMENT_CREATED
      TriggerEngine.publish(
        event_type: event_type, source: SOURCE, subject: self.class.subject(repository, event.number),
        project: repository.scope, data: data_for(repository, event, origin),
        dedup_key: dedup_key(repository, event_type, event)
      )
    end

    def data_for(repository, event, origin)
      text = bounded(event.body)
      data = {
        "repository" => { "id" => repository.id, "full_name" => repository.full_name, "provider" => provider(repository) },
        "pull_request" => {
          "number" => event.number, "title" => event.title, "url" => event.url, "source_branch" => event.source_branch,
          "target_branch" => event.target_branch, "author" => event.author
        }.compact,
        "actor" => event.actor.transform_keys(&:to_s).merge("is_me" => origin.present?),
        "origin" => origin,
        "text" => text,
        "external_resource" => {
          "provider" => provider(repository), "instance" => instance(repository),
          "external_id" => "#{self.class.repository_key(repository)}##{event.number}",
          "key" => "#{repository.full_name}##{event.number}", "url" => event.url
        }.compact
      }
      data.merge(event.review? ? review_data(event, text) : comment_data(repository, event, text)).compact
    end

    def review_data(event, text)
      { "review" => { "verdict" => event.verdict, "body" => text }.compact }
    end

    def comment_data(repository, event, text)
      {
        "comment" => {
          "id" => event.comment_id&.to_s, "author" => event.actor[:name], "text" => text, "file" => event.file,
          "line" => event.line, "reply_to" => event.reply_to&.to_s,
          "mentions_me" => Identity.mentioned?(repository.integration, event.body)
        }.compact
      }
    end

    # Which run wrote this, if Aixle did. The write may have gone through another
    # Aixle project's row for the same repository.
    def origin_for(repository, event)
      operation = matching_operation(repository, event)
      if operation
        chain = Array(run_chain(operation.workflow_run_id)) + [ operation.workflow_id ].compact
        return { "aixle" => true, "attributed" => true, "workflow_run_id" => operation.workflow_run_id,
                 "workflow_id" => operation.workflow_id, "chain" => chain, "depth" => chain.size }
      end
      return unless event.own || Identity.own?(repository.integration, event.actor)

      { "aixle" => true, "attributed" => false, "chain" => [], "depth" => 1 }
    end

    def matching_operation(repository, event)
      recent = ledger(repository).where(pull_request_number: event.number.to_s, state: %w[pending succeeded])
                                 .where(created_at: ATTRIBUTION_WINDOW.ago..).order(created_at: :desc).to_a
      if event.review?
        recent.select { |op| op.operation == "review" }.detect do |op|
          op.result.blank? || LEDGER_VERDICTS[op.result.to_h["verdict"].to_s] == event.verdict
        end
      else
        comment_operation(recent.select { |op| op.operation == "add_comment" }, repository, event)
      end
    end

    # A write the provider has not answered yet names no comment; it is Aixle's
    # only while the comment's author is not known to be someone else.
    def comment_operation(writes, repository, event)
      return writes.first if event.comment_id.blank?

      writes.detect { |op| op.result.to_h["id"].to_s == event.comment_id.to_s } ||
        (writes.detect { |op| op.result.blank? } unless someone_else?(repository, event))
    end

    def someone_else?(repository, event)
      provider = Identity.tracker_provider(repository.integration)
      provider&.identity.present? && event.actor.present? && !provider.own_actor?(event.actor)
    end

    def ledger(repository)
      same = Repository.joins(:integration)
                       .where(full_name: repository.full_name, integrations: { provider: provider(repository) })
      PullRequestOperation.where(repository_id: same.select(:id))
    end

    def run_chain(workflow_run_id)
      return [] unless workflow_run_id

      WorkflowRun.where(id: workflow_run_id).pick(Arel.sql("shared_context -> 'pull_request' -> 'chain'"))
    end

    def over_limits?(repository, event, origin)
      if origin["depth"].to_i >= MAX_CHAIN_DEPTH
        skip(repository, event, "chain_depth_limit")
      elsif recent_aixle_events(repository, event) >= PULL_REQUEST_BUDGET
        skip(repository, event, "pull_request_chain_budget")
      else
        false
      end
    end

    def recent_aixle_events(repository, event)
      TriggerEvent.where(project_id: repository.scope_id, source: SOURCE, subject: self.class.subject(repository, event.number))
                  .where(created_at: 1.hour.ago..)
                  .where("data -> 'origin' ->> 'aixle' = 'true'")
                  .count
    end

    def skip(repository, event, reason)
      Rails.logger.warn("[PullRequests::EventPipeline] #{reason}: repository #{repository.id} " \
                        "pull request #{event.number} — not published")
      true
    end

    # Two reviewers can submit at the same revision of a pull request, so the
    # reviewer is part of what makes a delivery the same one.
    def dedup_key(repository, event_type, event)
      discriminator = event.comment_id || event.revision || event.occurred_at
      Digest::SHA256.hexdigest(
        [ repository.scope_id, self.class.subject(repository, event.number), event_type,
          event.actor[:id] || event.actor[:name], discriminator ].join(":")
      )
    end

    def provider(repository) = repository.integration&.provider.to_s

    def instance(repository)
      URI.parse(repository.clone_url.to_s).host.presence || provider(repository)
    rescue URI::InvalidURIError
      provider(repository)
    end

    # Postgres refuses a NUL in jsonb text.
    def bounded(text)
      return nil if text.blank?

      text.to_s.delete("\u0000").truncate(TEXT_LIMIT, omission: "… [truncated]")
    end
  end
end
