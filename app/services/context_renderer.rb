# frozen_string_literal: true

class ContextRenderer
  TOKEN_BUDGET = (Settings.dig(:context, :token_budget) || 6000).to_i
  CHARS_PER_TOKEN = 4

  PRIORITY_ORDER = { critical: 0, important: 1, info: 2 }.freeze
  POSITION_ORDER = { top: 0, middle: 1, bottom: 2, footer: 3 }.freeze

  COMPRESSIBLE_TAGS = %w[previous-steps board-context custom-tools available-resources repositories].freeze

  def self.render(sections)
    return "" if sections.empty?

    sections = compress(sections) if over_budget?(sections)

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
    sections.sum { |s| s.content.length } / CHARS_PER_TOKEN
  end

  def self.over_budget?(sections)
    estimate_tokens(sections) > TOKEN_BUDGET
  end

  def self.compress(sections)
    compression_steps.each do |step|
      sections = step.call(sections)
      break unless over_budget?(sections)
    end
    sections
  end

  def self.compression_steps
    [
      method(:compress_previous_steps),
      method(:compress_board_comments),
      method(:compress_tool_descriptions),
      method(:compress_skills),
      method(:compress_repositories)
    ]
  end

  def self.replace_section(sections, tag, &block)
    sections.map do |s|
      next s if s.priority == :critical
      next s unless s.tag == tag

      new_content = block.call(s.content)
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
        if line.strip.start_with?("→") && line.strip.length > 100
          "#{line.strip.truncate(100)}\n"
        elsif line.strip.start_with?("→ data:")
          next nil
        else
          line
        end
      end.compact.join
    end
  end

  def self.compress_board_comments(sections)
    replace_section(sections, "board-context") do |content|
      in_comments = false
      comment_count = 0
      lines = content.lines
      lines.select do |line|
        if line.include?("### Recent Comments")
          in_comments = true
          true
        elsif in_comments && line.strip.start_with?("- **")
          comment_count += 1
          comment_count <= 3
        else
          true
        end
      end.join
    end
  end

  def self.compress_tool_descriptions(sections)
    replace_section(sections, "custom-tools") do |content|
      lines = content.lines
      lines.reject { |line| line.strip.start_with?("- Parameter", "  - ", "Parameters:") }.join
    end
  end

  def self.compress_skills(sections)
    replace_section(sections, "available-resources") do |content|
      lines = content.lines
      in_skill_detail = false
      lines.select do |line|
        if line.strip.start_with?("### ")
          in_skill_detail = false
          true
        elsif line.strip.start_with?("- **") || line.strip.start_with?("* **")
          in_skill_detail = true
          true
        elsif in_skill_detail && (line.strip.start_with?("  ") || line.strip.empty?)
          false
        else
          in_skill_detail = false
          true
        end
      end.join
    end
  end

  def self.compress_repositories(sections)
    replace_section(sections, "repositories") do |content|
      lines = content.lines
      lines.reject { |line| line.include?("Purpose:") || line.include?("purpose:") }.join
    end
  end

  private_class_method :compress, :compression_steps, :replace_section,
    :compress_previous_steps, :compress_board_comments,
    :compress_tool_descriptions, :compress_skills, :compress_repositories
end
