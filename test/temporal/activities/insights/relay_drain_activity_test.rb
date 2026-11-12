# frozen_string_literal: true

require "test_helper"

class Activities::Insights::RelayDrainActivityTest < ActiveSupport::TestCase
  test "sends what the ingest left in the outbox" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    session = create(:terminal_session, :running, user: user, project: project)
    integration = connect_to_insights!(project)
    create(:insights_otlp_batch, integration: integration, project: project, terminal_session: session)
    Insights::Client.stubs(:build).returns(FakeInsightsClient.new)

    result = run_activity(Activities::Insights::RelayDrainActivity)

    assert_equal({ integration.id.to_s => { "delivered" => 1, "claimed" => 1 } }, result)
    assert_equal 0, InsightsOtlpBatch.count
  end
end
