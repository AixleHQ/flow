# frozen_string_literal: true

require "test_helper"

class ContextRendererTest < ActiveSupport::TestCase
  test "renders empty array as empty string" do
    assert_equal "", ContextRenderer.render([])
  end

  test "renders single section with XML tags" do
    section = ContextSection.new(tag: "test", priority: :critical, content: "hello world")
    output = ContextRenderer.render([ section ])

    assert_includes output, '<test priority="critical">'
    assert_includes output, "hello world"
    assert_includes output, "</test>"
  end

  test "every open tag has a matching close tag" do
    sections = [
      ContextSection.new(tag: "alpha", priority: :critical, content: "a"),
      ContextSection.new(tag: "beta", priority: :info, content: "b")
    ]
    output = ContextRenderer.render(sections)

    assert_includes output, "<alpha"
    assert_includes output, "</alpha>"
    assert_includes output, "<beta"
    assert_includes output, "</beta>"
  end

  test "sections are sorted by position_hint first, then priority" do
    bottom_critical = ContextSection.new(tag: "bc", priority: :critical, content: "c", position_hint: :bottom)
    top_info = ContextSection.new(tag: "ti", priority: :info, content: "c", position_hint: :top)
    middle_important = ContextSection.new(tag: "mi", priority: :important, content: "c", position_hint: :middle)
    top_critical = ContextSection.new(tag: "tc", priority: :critical, content: "c", position_hint: :top)

    output = ContextRenderer.render([ bottom_critical, top_info, middle_important, top_critical ])

    tc_pos = output.index("<tc ")
    ti_pos = output.index("<ti ")
    mi_pos = output.index("<mi ")
    bc_pos = output.index("<bc ")

    assert tc_pos < ti_pos, "top/critical should come before top/info"
    assert ti_pos < mi_pos, "top/info should come before middle/important"
    assert mi_pos < bc_pos, "middle/important should come before bottom/critical"
  end

  test "multiple sections are joined by double newlines" do
    sections = [
      ContextSection.new(tag: "a", priority: :critical, content: "content a"),
      ContextSection.new(tag: "b", priority: :info, content: "content b")
    ]
    output = ContextRenderer.render(sections)

    assert_includes output, "</a>\n\n<b"
  end

  test "content is stripped inside XML tags" do
    section = ContextSection.new(tag: "test", priority: :info, content: "  padded  ")
    output = ContextRenderer.render([ section ])

    assert_includes output, "padded"
    assert_not_includes output, "  padded  "
  end

  test "priority attribute is embedded in open tag" do
    section = ContextSection.new(tag: "rules", priority: :important, content: "rule text")
    output = ContextRenderer.render([ section ])

    assert_match(/<rules priority="important">/, output)
  end

  # -- Story 28.1: Token Budget Compression --

  test "no compression when under budget" do
    small_content = "x" * 100
    sections = [
      ContextSection.new(tag: "previous-steps", priority: :info, content: small_content),
      ContextSection.new(tag: "board-context", priority: :important, content: small_content)
    ]
    output = ContextRenderer.render(sections)
    assert_includes output, small_content
  end

  test "compression applied when over budget" do
    large_content = "x" * 25_000
    sections = [
      ContextSection.new(tag: "critical-rules", priority: :critical, content: "Must keep this"),
      ContextSection.new(tag: "previous-steps", priority: :info, content: build_previous_steps_content(large_content))
    ]
    output = ContextRenderer.render(sections)
    assert output.length < large_content.length + 500
  end

  test "critical sections never compressed" do
    critical_content = "Critical rules " + "y" * 20_000
    compressible_content = build_previous_steps_content("z" * 10_000)
    sections = [
      ContextSection.new(tag: "critical-rules", priority: :critical, content: critical_content),
      ContextSection.new(tag: "previous-steps", priority: :info, content: compressible_content)
    ]
    output = ContextRenderer.render(sections)
    assert_includes output, critical_content.strip
  end

  test "all section tags preserved after compression" do
    large = "a" * 25_000
    sections = [
      ContextSection.new(tag: "critical-rules", priority: :critical, content: "rules"),
      ContextSection.new(tag: "previous-steps", priority: :info, content: build_previous_steps_content(large)),
      ContextSection.new(tag: "board-context", priority: :important, content: build_board_context_with_comments(6))
    ]
    output = ContextRenderer.render(sections)

    assert_includes output, "<critical-rules"
    assert_includes output, "</critical-rules>"
    assert_includes output, "<previous-steps"
    assert_includes output, "</previous-steps>"
    assert_includes output, "<board-context"
    assert_includes output, "</board-context>"
  end

  test "progressive compression stops when under budget" do
    slightly_over = "w" * ((ContextRenderer::TOKEN_BUDGET * ContextRenderer::CHARS_PER_TOKEN) + 500)
    sections = [
      ContextSection.new(tag: "previous-steps", priority: :info,
        content: build_previous_steps_content(slightly_over)),
      ContextSection.new(tag: "board-context", priority: :important, content: "small board content")
    ]
    output = ContextRenderer.render(sections)
    assert_includes output, "small board content"
  end

  test "board comments reduced to 3 during compression" do
    big_filler = "f" * 25_000
    board_content = build_board_context_with_comments(5)
    sections = [
      ContextSection.new(tag: "previous-steps", priority: :info, content: big_filler),
      ContextSection.new(tag: "board-context", priority: :important, content: board_content)
    ]
    output = ContextRenderer.render(sections)

    comment_matches = output.scan(/\*\*Author\d+\*\*/)
    assert comment_matches.length <= 3
  end

  private

  def build_previous_steps_content(filler)
    <<~MD
      ### Previous Steps

      - Step 1: Analyze (completed)
        → #{filler}
        → data: {"files": 42}
      - Step 2: Review (completed)
        → Short note
    MD
  end

  def build_board_context_with_comments(count)
    comments = (1..count).map { |i| "- **Author#{i}** (human): Comment body #{i}" }.join("\n")
    <<~MD
      ## Board Task Context

      - **Board:** Test Board
      - **Task:** Test Task (id: 1)

      ### Recent Comments
      #{comments}

      Use board MCP tools to interact with the board.
    MD
  end
end
