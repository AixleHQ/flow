# frozen_string_literal: true

require "test_helper"

class ContextBuilders::AixleBuilderTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :aixle_builder, user: @user, project: @project)
  end

  test "applies to builder sessions only" do
    assert ContextBuilders::AixleBuilder.new(@session).applicable?
    plain = create(:terminal_session, :agent_session, user: @user, project: @project)
    assert_not ContextBuilders::AixleBuilder.new(plain).applicable?
  end

  test "carries the role, a project snapshot and the tool catalog" do
    sections = ContextBuilders::AixleBuilder.new(@session).build.index_by(&:tag)

    assert_equal %w[aixle_builder_project aixle_builder_role aixle_builder_tools], sections.keys.sort
    assert_includes sections["aixle_builder_project"].content, "(id #{@project.id})"
    assert_includes sections["aixle_builder_tools"].content, "`create_workflow_trigger`"
  end

  test "every tool the role names is one the builder is served" do
    role = ContextBuilders::AixleBuilder.new(@session).build.find { |s| s.tag == "aixle_builder_role" }.content
    served = Tools::BuilderToolset.definitions.map { |d| d.name.to_s }
    named = role.scan(/`([a-z]+(?:_[a-z]+)+)`/).flatten.uniq
    tool_like = named.select { |n| n.match?(/\A(get|list|create|update|delete|install|uninstall|search|setup|duplicate|trigger|validate|cancel|skip|approve|retry)_/) }

    assert_empty tool_like - served
  end

  test "the builder's whole context stays well inside a runtime's instruction-file limit" do
    rendered = SessionContextConstructor.build(@session)

    assert_operator rendered.bytesize, :<, 28_000
    assert_not_includes rendered, "<output-rules"
  end
end
