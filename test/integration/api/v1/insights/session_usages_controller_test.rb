# frozen_string_literal: true

require "test_helper"

class Api::V1::Insights::SessionUsagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @owner, share_usage_with_insights: true)
    @token = @project.regenerate_insights_connection_token!
  end

  test "project probe returns project metadata" do
    get api_v1_insights_project_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @project.id, body["id"]
    assert_equal @project.slug, body["slug"]
    assert_equal @company.id, body["company_id"]
    assert body["share_usage_with_insights"]
  end

  test "members lists owner and collaborators" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    @project.add_collaborator(collaborator)

    get api_v1_insights_members_path, headers: auth_headers

    assert_response :success
    members = JSON.parse(response.body).fetch("members")
    emails = members.map { |m| m["email"] }
    assert_includes emails, @owner.email
    assert_includes emails, collaborator.email
  end

  test "missing token returns 401" do
    get api_v1_insights_project_path

    assert_response :unauthorized
  end

  test "invalid token returns 401" do
    get api_v1_insights_project_path, headers: { "Authorization" => "Bearer afli_invalid" }

    assert_response :unauthorized
  end

  test "token becomes invalid after sharing is turned off because digest is cleared" do
    @project.update!(share_usage_with_insights: false)

    get api_v1_insights_project_path, headers: auth_headers

    assert_response :unauthorized
    assert_nil @project.reload.insights_connection_token_digest
  end

  test "valid digest with sharing disabled returns 403 insights_sharing_disabled" do
    # Bypass the clear-on-disable callback to assert the hard gate independently.
    @project.update_columns(share_usage_with_insights: false)

    get api_v1_insights_project_path, headers: auth_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "insights_sharing_disabled", body["code"]
  end

  test "session_usages returns completed sessions with usage and omits sensitive fields" do
    included = create_finished_session_with_usage(input_tokens: 100, output_tokens: 50, cost_cents: 12)
    create_finished_session_with_usage # another eligible row
    create_running_session_with_usage
    create_auth_setup_with_usage
    create_finished_session_without_usage

    get api_v1_insights_session_usages_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    usages = body.fetch("session_usages")
    assert_equal 2, usages.size

    row = usages.find { |u| u["external_id"] == included.id.to_s }
    assert_equal @owner.email, row.dig("user", "email")
    assert_equal @project.slug, row.dig("project", "slug")
    assert_equal "claude_code", row["agent_type"]
    assert_equal 100, row["tokens_in"]
    assert_equal 50, row["tokens_out"]
    assert_in_delta 0.12, row["cost_usd"], 0.0001

    forbidden_keys = %w[initial_prompt events_data route_token mcp_key metadata session_config]
    usages.each do |usage|
      forbidden_keys.each { |key| assert_not usage.key?(key), "must not expose #{key}" }
    end
  end

  test "session_usages pagination with since and after_id" do
    older = create_finished_session_with_usage(finished_at: 2.days.ago)
    newer = create_finished_session_with_usage(finished_at: 1.day.ago)

    get api_v1_insights_session_usages_path,
        params: { since: older.finished_at.iso8601(3), after_id: older.id, limit: 10 },
        headers: auth_headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("session_usages").map { |u| u["external_id"] }
    assert_equal [ newer.id.to_s ], ids
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def create_finished_session_with_usage(input_tokens: 10, output_tokens: 5, cost_cents: 1, finished_at: 1.hour.ago)
    session = create(
      :terminal_session, :agent_session, :collected,
      user: @owner,
      project: @project,
      finished_at: finished_at,
      started_at: finished_at - 10.minutes
    )
    UsageStatistic.create!(
      terminal_session: session,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_write_tokens: 0,
      cache_read_tokens: 0,
      tokens: input_tokens + output_tokens,
      cost_cents: cost_cents,
      total_cents_precise: cost_cents,
      models: [ "claude-sonnet-4" ],
      source: "otlp"
    )
    session
  end

  def create_running_session_with_usage
    session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    UsageStatistic.create!(
      terminal_session: session,
      input_tokens: 1,
      output_tokens: 1,
      tokens: 2,
      cost_cents: 1,
      models: [ "claude-sonnet-4" ]
    )
    session
  end

  def create_auth_setup_with_usage
    session = create(
      :terminal_session, :auth_setup, :collected,
      user: @owner,
      project: nil,
      company_id: @company.id
    )
    UsageStatistic.create!(
      terminal_session: session,
      input_tokens: 1,
      output_tokens: 1,
      tokens: 2,
      cost_cents: 1,
      models: [ "claude-sonnet-4" ]
    )
    session
  end

  def create_finished_session_without_usage
    create(:terminal_session, :agent_session, :collected, user: @owner, project: @project)
  end
end
