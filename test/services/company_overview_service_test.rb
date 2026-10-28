# frozen_string_literal: true

require "test_helper"

class CompanyOverviewServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "sums the tokens and start-to-finish time of the project's sessions" do
    started = 3.hours.ago
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "finished",
                                              started_at: started, finished_at: started + 30.minutes, total_tokens: 1_200)
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "failed",
                                              started_at: started, finished_at: started + 15.minutes, total_tokens: 800)
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "queued")
    other_project = create(:project, company: @company, owner: @user)
    create(:terminal_session, :agent_session, project: other_project, user: @user, state: "finished",
                                              started_at: started, finished_at: started + 2.hours, total_tokens: 5_000)

    result = CompanyOverviewService.new(@company, project: @project).call

    assert_equal 2_000, result.total_tokens
    assert_equal 45.minutes.to_i, result.session_seconds
  end

  test "a running session counts up to now" do
    create(:terminal_session, :agent_session, :running, project: @project, user: @user, started_at: 10.minutes.ago)

    result = CompanyOverviewService.new(@company, project: @project).call

    assert_in_delta 10.minutes.to_i, result.session_seconds, 5
  end

  test "reports zero for a project without sessions" do
    result = CompanyOverviewService.new(@company, project: @project).call

    assert_equal 0, result.total_tokens
    assert_equal 0, result.session_seconds
  end
end
