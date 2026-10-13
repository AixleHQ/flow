# frozen_string_literal: true

require "test_helper"

class ContextBuilders::ProjectMemoryTest < ActiveSupport::TestCase
  test "enabled memory adds retrieval guidance without fetching memories" do
    project = create(:project, :standalone, memory_enabled: true)
    session = create(:terminal_session, :agent_session, :running, project: project, user: project.owner)
    Engram::Client.stubs(:configured?).returns(true)

    result = SessionContextConstructor.build_result(session)
    section = result.sections.find { |value| value.tag == "project-memory" }
    assert section
    assert_includes section.content, "memory_search"
    assert_includes section.content, "reference data"
    assert_includes section.content, "pending"
    assert_equal 0, MemoryRetrieval.count
  end

  test "disabled sessions do not receive memory guidance" do
    project = create(:project, :standalone, memory_enabled: true)
    session = create(:terminal_session, :agent_session, :running, project: project, user: project.owner,
                     metadata: { "memory_disabled" => true })
    Engram::Client.stubs(:configured?).returns(true)

    assert_not SessionContextConstructor.build_result(session).sections.any? { |value| value.tag == "project-memory" }
  end
end
