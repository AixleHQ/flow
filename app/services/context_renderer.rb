# frozen_string_literal: true

class ContextRenderer
  TOKEN_BUDGET = (Settings.dig(:context, :token_budget) || 6000).to_i
  CHARS_PER_TOKEN = 4

  PRIORITY_ORDER = { critical: 0, important: 1, info: 2 }.freeze
  POSITION_ORDER = { top: 0, middle: 1, bottom: 2, footer: 3 }.freeze

  def self.render(sections)
    render_with_metadata(sections)[:content]
  end

  def self.render_with_metadata(sections)
    original = render_sections(sections)
    prepared = over_budget?(sections) ? compress_previous_steps(sections) : sections
    content = prepared.equal?(sections) ? original : render_sections(prepared)
    compressed_tags = sections.zip(prepared).filter_map do |before, after|
      before.tag if before.content != after.content
    end.uniq

    {
      content: content,
      original_rendered_content_length: original.length,
      rendered_content_length: content.length,
      estimated_tokens_before: estimate_text_tokens(original),
      estimated_tokens_after: estimate_text_tokens(content),
      token_budget: TOKEN_BUDGET,
      over_budget: estimate_text_tokens(content) > TOKEN_BUDGET,
      compressed_tags: compressed_tags
    }
  end

  def self.render_sections(sections)
    # sort_by is not stable, so equal (position, priority) pairs would otherwise
    # render in an arbitrary order between runs — and the last critical section
    # is exactly the one whose placement matters (see ContextBuilders::
    # SessionCompletion). The index tiebreak keeps builder order.
    sorted = sections.each_with_index.sort_by do |s, i|
      [ POSITION_ORDER[s.position_hint], PRIORITY_ORDER[s.priority], i ]
    end

    sorted.map { |s, _i| render_section(s) }.join("\n\n")
  end

  def self.render_section(section)
    <<~XML.rstrip
      <#{section.tag} priority="#{section.priority}">

      #{section.content.strip}

      </#{section.tag}>
    XML
  end

  def self.estimate_tokens(sections)
    estimate_text_tokens(render_sections(sections))
  end

  def self.estimate_text_tokens(text)
    (text.length + CHARS_PER_TOKEN - 1) / CHARS_PER_TOKEN
  end

  def self.over_budget?(sections)
    estimate_tokens(sections) > TOKEN_BUDGET
  end

  def self.replace_section(sections, tag, &block)
    sections.map do |s|
      next s if s.priority == :critical
      next s unless s.tag == tag

      new_content = block.call(s.content)
      next s if new_content.blank? || new_content == s.content

      ContextSection.new(
        tag: s.tag, priority: s.priority, content: new_content,
        position_hint: s.position_hint, builder_name: s.builder_name
      )
    end
  end

  def self.compress_previous_steps(sections)
    replace_section(sections, "previous-steps") do |content|
      lines = content.lines
      lines.map do |line|
        if line.strip.start_with?("→ data:")
          next nil
        elsif line.strip.start_with?("→") && line.strip.length > 100
          "#{line.strip.truncate(100)}\n"
        else
          line
        end
      end.compact.join
    end
  end

  private_class_method :render_sections, :estimate_text_tokens, :replace_section, :compress_previous_steps
end
