# frozen_string_literal: true

class ContextResult
  attr_reader :session, :sections, :applied_builders, :skipped_builders,
              :built_at, :build_time_ms, :config_resolution

  def initialize(session:, sections:, applied_builders:, skipped_builders:, built_at:, build_time_ms:, config_resolution: nil)
    @session = session
    @sections = sections.freeze
    @applied_builders = applied_builders.freeze
    @skipped_builders = skipped_builders.freeze
    @built_at = built_at
    @build_time_ms = build_time_ms
    @config_resolution = config_resolution&.freeze
  end

  def render
    @rendered ||= ContextRenderer.render(@sections)
  end
  alias_method :to_s, :render

  def total_content_length
    sections.sum { |s| s.content.length }
  end

  def to_json_hash
    hash = {
      session_id: session.id,
      session_type: detect_session_type,
      project_id: session.project_id,
      built_at: built_at.iso8601,
      build_time_ms: build_time_ms,
      total_content_length: total_content_length,
      applied_builders: applied_builders,
      skipped_builders: skipped_builders,
      sections: sections.map { |s| section_metadata(s) }
    }
    hash[:config_resolution] = config_resolution if config_resolution.present?
    hash
  end

  def to_json(*args)
    to_json_hash.to_json(*args)
  end

  private

  def detect_session_type
    if session.step_run&.workflow_run&.board_task.present?
      "board_triggered"
    elsif session.step_run.present?
      "workflow_step"
    else
      "standalone"
    end
  end

  def section_metadata(s)
    {
      tag: s.tag,
      priority: s.priority,
      position_hint: s.position_hint,
      builder: s.builder_name,
      content_length: s.content.length
    }
  end
end
