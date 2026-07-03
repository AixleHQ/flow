# frozen_string_literal: true

require "test_helper"

class ContextBuilders::BmadMethodTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  # -- AC #3: applicable? returns false when bmad_enabled is false/nil --

  test "applicable? returns false when bmad_enabled is false" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => false })

    builder = ContextBuilders::BmadMethod.new(session)
    assert_not builder.applicable?
  end

  test "applicable? returns false when bmad_enabled is absent" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: {})

    builder = ContextBuilders::BmadMethod.new(session)
    assert_not builder.applicable?
  end

  test "applicable? returns false when session_config is empty" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: {})

    builder = ContextBuilders::BmadMethod.new(session)
    assert_not builder.applicable?
  end

  # -- AC #1: applicable? returns true when bmad_enabled is true --

  test "applicable? returns true when bmad_enabled is true" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    builder = ContextBuilders::BmadMethod.new(session)
    assert builder.applicable?
  end

  # -- AC #1 & #4: build produces bmad-method section with correct tag, priority, position --

  test "build produces bmad-method section with correct tag, priority, and position" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    sections = ContextBuilders::BmadMethod.new(session).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "bmad-method", section.tag
    assert_equal :info, section.priority
    assert_equal :middle, section.position_hint
    assert_equal "bmad_method", section.builder_name
  end

  # -- AC #2: content includes references to BMAD files, config, output folder --

  test "content includes BMAD root path" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "/workspace/_bmad/"
  end

  test "content includes core config path" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "/workspace/_bmad/core/config.yaml"
  end

  test "content includes output folder reference" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "/workspace/outputs/"
  end

  test "content includes default modules" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "bmm"
  end

  test "content includes custom modules when specified" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true, "bmad_modules" => %w[bmm cis bmb] })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "bmm, cis, bmb"
  end

  test "content includes usage instructions" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    content = ContextBuilders::BmadMethod.new(session).build.first.content
    assert_includes content, "slash-commands"
    assert_includes content, "BMAD Method"
  end

  # -- AC #5 equivalent: BUILDERS registration position --

  test "BmadMethod is in BUILDERS after Resources and before OutputRules" do
    builders = SessionContextConstructor::BUILDERS
    resources_idx = builders.index(ContextBuilders::Resources)
    bmad_idx = builders.index(ContextBuilders::BmadMethod)
    output_idx = builders.index(ContextBuilders::OutputRules)

    assert_not_nil bmad_idx, "BmadMethod must be in BUILDERS"
    assert bmad_idx > resources_idx, "BmadMethod must be after Resources"
    assert bmad_idx < output_idx, "BmadMethod must be before OutputRules"
  end

  # -- AC #5: applicable? returns false when bmad_install_status is "failed" --

  test "applicable? returns false when bmad_install_status is failed" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })
    session.update_column(:context_metadata, { "bmad_install_status" => "failed", "bmad_install_error" => "timed out" })

    builder = ContextBuilders::BmadMethod.new(session)
    assert_not builder.applicable?
  end

  test "applicable? returns true when bmad_install_status is success" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })
    session.update_column(:context_metadata, { "bmad_install_status" => "success" })

    builder = ContextBuilders::BmadMethod.new(session)
    assert builder.applicable?
  end

  test "applicable? returns true when context_metadata has no install status" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    builder = ContextBuilders::BmadMethod.new(session)
    assert builder.applicable?
  end

  # -- Integration: full context build --

  test "SessionContextConstructor includes bmad_method when bmad_enabled" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: { "bmad_enabled" => true })

    result = SessionContextConstructor.build_result(session)
    assert_includes result.applied_builders, "bmad_method"

    bmad_section = result.sections.find { |s| s.tag == "bmad-method" }
    assert_not_nil bmad_section
    assert_equal :info, bmad_section.priority
  end

  test "SessionContextConstructor skips bmad_method when bmad not enabled" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      session_config: {})

    result = SessionContextConstructor.build_result(session)
    assert_includes result.skipped_builders, "bmad_method"

    bmad_section = result.sections.find { |s| s.tag == "bmad-method" }
    assert_nil bmad_section
  end
end
