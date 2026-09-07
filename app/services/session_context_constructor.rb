# frozen_string_literal: true

class SessionContextConstructor
  BUILDERS = [
    ContextBuilders::CriticalRules,
    ContextBuilders::AixleBuilder,
    ContextBuilders::AgentRole,
    ContextBuilders::SessionInfo,
    ContextBuilders::Workspace,
    ContextBuilders::WorkflowContext,
    ContextBuilders::BoardContext,
    ContextBuilders::Tools,
    ContextBuilders::Resources,
    ContextBuilders::ConfigItems,
    ContextBuilders::BmadMethod,
    ContextBuilders::OutputRules,
    # Last on purpose: ties in the renderer's sort are broken by this order, so
    # the completion mandate is the final thing the agent reads.
    ContextBuilders::SessionCompletion
  ].freeze

  def self.build(session)
    new(session).build.render
  end

  def self.build_result(session)
    new(session).build
  end

  def initialize(session)
    @session = session
  end

  def build
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    builder_instances = BUILDERS.map { |klass| klass.new(@session) }
    applicable = builder_instances.select(&:applicable?)
    skipped = builder_instances.reject(&:applicable?)

    sections = applicable.flat_map(&:build).compact

    config_resolution = begin
      SessionConfigResolver.resolve_with_breakdown(@session)
    rescue StandardError => e
      Rails.logger.warn("[SessionContextConstructor] Config resolution breakdown failed: #{e.message}")
      nil
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

    ContextResult.new(
      session: @session,
      sections: sections,
      applied_builders: applicable.map(&:name),
      skipped_builders: skipped.map(&:name),
      built_at: Time.current,
      build_time_ms: elapsed_ms,
      config_resolution: config_resolution
    )
  end
end
