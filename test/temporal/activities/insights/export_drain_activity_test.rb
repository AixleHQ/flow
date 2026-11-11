# frozen_string_literal: true

require "test_helper"

class Activities::Insights::ExportDrainActivityTest < ActiveSupport::TestCase
  test "sends the sessions still due to Insights" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    session = create(:terminal_session, :running, user: user, project: project)
    connect_to_insights!(project)
    create(:llm_call, terminal_session: session)
    Insights::Export.enqueue(session)
    insights = FakeInsightsClient.new
    Insights::Client.stubs(:build).returns(insights)

    result = run_activity(Activities::Insights::ExportDrainActivity)

    assert_equal({ "delivered" => 1, "swept" => 1 }, result)
    assert_equal "delivered", InsightsSessionExport.find_by!(terminal_session: session).state
  end
end
