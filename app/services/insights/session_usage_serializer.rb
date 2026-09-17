# frozen_string_literal: true

module Insights
  # Safe payload for Insights ToolEvent ingest. Never includes prompts,
  # transcripts, events_data, route/mcp keys, or config-item values.
  class SessionUsageSerializer
    def self.call(session:, usage_statistic:)
      new(session:, usage_statistic:).call
    end

    def initialize(session:, usage_statistic:)
      @session = session
      @stat = usage_statistic
    end

    def call
      {
        external_id: @session.id.to_s,
        occurred_at: (@session.finished_at || @session.updated_at)&.iso8601(3),
        started_at: @session.started_at&.iso8601(3),
        finished_at: @session.finished_at&.iso8601(3),
        user: user_payload,
        project: project_payload,
        agent_type: @session.agent_type,
        session_type: @session.session_type,
        models: Array(@stat.models),
        tokens_in: @stat.input_tokens,
        tokens_out: @stat.output_tokens,
        cache_write_tokens: @stat.cache_write_tokens,
        cache_read_tokens: @stat.cache_read_tokens,
        tokens_total: @stat.total_tokens,
        cost_usd: cost_usd
      }
    end

    private

    def user_payload
      user = @session.user
      {
        id: user.id,
        email: user.email,
        name: user.name
      }
    end

    def project_payload
      project = @session.project
      {
        id: project.id,
        slug: project.slug,
        name: project.name
      }
    end

    def cost_usd
      precise = @stat.total_cents_precise
      if precise.present? && precise.to_d.positive?
        (precise.to_d / 100).to_f
      else
        @stat.cost_cents.to_f / 100.0
      end
    end
  end
end
