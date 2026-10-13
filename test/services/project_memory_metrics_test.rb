# frozen_string_literal: true

require "test_helper"

class ProjectMemoryMetricsTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @session = create(:terminal_session, project: @project, user: @project.owner,
                      metadata: { "project_memory" => { "retrieval_calls" => 2, "retrieved_tokens" => 350, "captures" => 1 } })
    @export = ProjectMemoryMetrics.new(project: @project, reviewer: @project.owner)
  end

  test "exports reported usage separately from memory estimates without finding contents" do
    UsageStatistic.create!(terminal_session: @session, input_tokens: 100, output_tokens: 20, cache_read_tokens: 60,
                           cost_cents: 7, total_cents_precise: "6.2", source: "otlp", events_count: 1, models: [ "model-a" ],
                           events_data: [ { "prompt" => "private_provider_payload" } ])
    @project.project_memories.create!(title: "Finding", content: "private_finding_body", topic_key: "finding")
    row = @export.call(session_ids: [ @session.id ]).sole

    assert_equal 180, row[:usage][:total_tokens]
    assert_equal 60, row[:usage][:cache_read_tokens]
    assert_equal "6.2", row[:usage][:cost_cents_precise]
    assert row[:token_measurement_available]
    assert_equal 350, row[:memory][:retrieved_tokens_estimate]
    assert_equal 2, row[:memory][:retrieval_calls]
    assert_equal [ "model-a" ], row[:usage][:models]
    assert_nil row[:cohort]
    assert_not row.to_json.include?("private_provider_payload")
    assert_not row.to_json.include?("private_finding_body")
  end

  test "missing usage stays unknown rather than becoming zero" do
    row = @export.call(session_ids: [ @session.id ]).sole

    assert_nil row[:usage]
    refute row[:token_measurement_available]
  end

  test "credit based Kiro usage does not imply measured zero tokens" do
    @session.update!(agent_type: "kiro_cli")
    UsageStatistic.create!(terminal_session: @session, cost_cents: 5, source: "kiro_cli_credits", events_count: 1)
    row = @export.call(session_ids: [ @session.id ]).sole

    assert_equal 5, row[:usage][:cost_cents]
    assert_nil row[:usage][:cost_cents_precise]
    refute row[:token_measurement_available]
  end

  test "foreign and unknown session selectors deny the whole export" do
    project = create(:project, :standalone)
    foreign = create(:terminal_session, project: project, user: project.owner)
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ @session.id, foreign.id ]) }
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ -1 ]) }
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ TerminalSession.maximum(:id) + 1 ]) }
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: []) }
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: Array.new(101, @session.id)) }
  end

  test "viewer or revoked membership cannot export even when still project owner" do
    membership = @project.owner.company_memberships.active.find_by!(company: @project.company)
    membership.update!(role: "viewer")
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ @session.id ]) }
    membership.update_column(:state, "revoked")
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ @session.id ]) }
  end

  test "company admin can export but ordinary collaborators cannot" do
    admin = create(:user, company: @project.company, membership_role: "admin")
    rows = ProjectMemoryMetrics.new(project: @project, reviewer: admin).call(session_ids: [ @session.id ])
    assert_equal @session.id, rows.sole[:session_id]
    collaborator = create(:user, company: @project.company)
    @project.project_collaborators.create!(user: collaborator)
    assert_raises(ProjectMemoryMetrics::Error) do
      ProjectMemoryMetrics.new(project: @project, reviewer: collaborator).call(session_ids: [ @session.id ])
    end
  end

  test "a session with inconsistent tenant ownership is excluded" do
    other = create(:company)
    @session.update_column(:company_id, other.id)
    assert_raises(ProjectMemoryMetrics::Error) { @export.call(session_ids: [ @session.id ]) }
  end
end
