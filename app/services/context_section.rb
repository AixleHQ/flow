# frozen_string_literal: true

class ContextSection
  PRIORITIES = %i[critical important info].freeze
  POSITIONS  = %i[top middle bottom].freeze

  attr_reader :tag, :priority, :content, :position_hint, :builder_name

  def initialize(tag:, priority:, content:, position_hint: :middle, builder_name: nil)
    raise ArgumentError, "tag required" if tag.to_s.strip.empty?
    raise ArgumentError, "unknown priority: #{priority}" unless PRIORITIES.include?(priority)
    raise ArgumentError, "unknown position: #{position_hint}" unless POSITIONS.include?(position_hint)
    raise ArgumentError, "content required" if content.to_s.strip.empty?

    @tag = tag.to_s.freeze
    @priority = priority
    @content = content.freeze
    @position_hint = position_hint
    @builder_name = builder_name&.to_s&.freeze

    freeze
  end

  def critical?
    priority == :critical
  end

  def to_h
    {
      tag: tag,
      priority: priority,
      position_hint: position_hint,
      builder_name: builder_name,
      content_length: content.length
    }
  end
end
