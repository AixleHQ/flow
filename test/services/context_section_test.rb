# frozen_string_literal: true

require "test_helper"

class ContextSectionTest < ActiveSupport::TestCase
  test "creates section with valid attributes and exposes readers" do
    section = ContextSection.new(
      tag: "test",
      priority: :critical,
      content: "hello",
      position_hint: :top,
      builder_name: "critical_rules"
    )

    assert_equal "test", section.tag
    assert_equal :critical, section.priority
    assert_equal "hello", section.content
    assert_equal :top, section.position_hint
    assert_equal "critical_rules", section.builder_name
  end

  test "critical? returns true for critical priority" do
    section = ContextSection.new(tag: "t", priority: :critical, content: "c")
    assert section.critical?
  end

  test "critical? returns false for non-critical priority" do
    section = ContextSection.new(tag: "t", priority: :important, content: "c")
    assert_not section.critical?

    section2 = ContextSection.new(tag: "t", priority: :info, content: "c")
    assert_not section2.critical?
  end

  test "to_h returns expected structure with content_length" do
    section = ContextSection.new(
      tag: "test",
      priority: :critical,
      content: "hello",
      position_hint: :top,
      builder_name: "critical_rules"
    )

    expected = {
      tag: "test",
      priority: :critical,
      position_hint: :top,
      builder_name: "critical_rules",
      content_length: 5
    }

    assert_equal expected, section.to_h
  end

  test "defaults position_hint to :middle" do
    section = ContextSection.new(tag: "t", priority: :info, content: "c")
    assert_equal :middle, section.position_hint
  end

  test "defaults builder_name to nil" do
    section = ContextSection.new(tag: "t", priority: :info, content: "c")
    assert_nil section.builder_name
  end

  test "raises ArgumentError for unknown priority" do
    error = assert_raises(ArgumentError) do
      ContextSection.new(tag: "t", priority: :unknown, content: "c")
    end
    assert_match(/unknown priority: unknown/, error.message)
  end

  test "raises ArgumentError for unknown position_hint" do
    error = assert_raises(ArgumentError) do
      ContextSection.new(tag: "t", priority: :critical, content: "c", position_hint: :nowhere)
    end
    assert_match(/unknown position/, error.message)
  end

  test "raises ArgumentError for blank tag" do
    error = assert_raises(ArgumentError) do
      ContextSection.new(tag: "", priority: :critical, content: "c")
    end
    assert_match(/tag required/, error.message)
  end

  test "raises ArgumentError for blank content" do
    error = assert_raises(ArgumentError) do
      ContextSection.new(tag: "t", priority: :critical, content: "")
    end
    assert_match(/content required/, error.message)
  end

  test "section is frozen after creation" do
    section = ContextSection.new(tag: "t", priority: :critical, content: "c")
    assert section.frozen?
    assert_raises(FrozenError) { section.instance_variable_set(:@tag, "x") }
  end

  test "tag is converted to string and frozen" do
    section = ContextSection.new(tag: :symbol_tag, priority: :info, content: "c")
    assert_equal "symbol_tag", section.tag
    assert section.tag.frozen?
  end

  test "content is frozen" do
    section = ContextSection.new(tag: "t", priority: :info, content: "some content")
    assert section.content.frozen?
  end
end
