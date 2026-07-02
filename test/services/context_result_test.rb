# frozen_string_literal: true

require "test_helper"

class ContextResultTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    @sections = [
      ContextSection.new(tag: "test", priority: :critical, content: "hello", position_hint: :top, builder_name: "test_builder")
    ]
  end

  test "render delegates to ContextRenderer" do
    result = ContextResult.new(
      session: @session, sections: @sections,
      applied_builders: [ "test_builder" ], skipped_builders: [],
      built_at: Time.current, build_time_ms: 1.5
    )

    assert_includes result.render, "<test"
    assert_includes result.render, "hello"
    assert_includes result.render, "</test>"
  end

  test "total_content_length sums content lengths" do
    sections = [
      ContextSection.new(tag: "a", priority: :info, content: "12345"),
      ContextSection.new(tag: "b", priority: :info, content: "1234567890")
    ]
    result = ContextResult.new(
      session: @session, sections: sections,
      applied_builders: [ "a", "b" ], skipped_builders: [],
      built_at: Time.current, build_time_ms: 1.0
    )

    assert_equal 15, result.total_content_length
  end

  test "to_json_hash returns expected structure" do
    built_at = Time.current
    result = ContextResult.new(
      session: @session, sections: @sections,
      applied_builders: [ "test_builder" ], skipped_builders: [ "skipped_one" ],
      built_at: built_at, build_time_ms: 2.5
    )

    hash = result.to_json_hash
    assert_equal @session.id, hash[:session_id]
    assert_equal "standalone", hash[:session_type]
    assert_equal @project.id, hash[:project_id]
    assert_equal built_at.iso8601, hash[:built_at]
    assert_in_delta(2.5, hash[:build_time_ms])
    assert_equal 5, hash[:total_content_length]
    assert_equal [ "test_builder" ], hash[:applied_builders]
    assert_equal [ "skipped_one" ], hash[:skipped_builders]
    assert_equal 1, hash[:sections].length
    assert_equal "test", hash[:sections].first[:tag]
    assert_equal :critical, hash[:sections].first[:priority]
    assert_equal 5, hash[:sections].first[:content_length]
  end

  test "detect_session_type returns standalone for regular session" do
    result = ContextResult.new(
      session: @session, sections: @sections,
      applied_builders: [], skipped_builders: [],
      built_at: Time.current, build_time_ms: 0
    )

    assert_equal "standalone", result.to_json_hash[:session_type]
  end

  test "sections array is frozen" do
    result = ContextResult.new(
      session: @session, sections: @sections,
      applied_builders: [], skipped_builders: [],
      built_at: Time.current, build_time_ms: 0
    )

    assert result.sections.frozen?
    assert result.applied_builders.frozen?
    assert result.skipped_builders.frozen?
  end

  test "to_json returns valid JSON string" do
    result = ContextResult.new(
      session: @session, sections: @sections,
      applied_builders: [ "test" ], skipped_builders: [],
      built_at: Time.current, build_time_ms: 1.0
    )

    parsed = JSON.parse(result.to_json)
    assert_equal @session.id, parsed["session_id"]
  end
end
