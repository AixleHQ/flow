# frozen_string_literal: true

require "test_helper"

class Activities::Coder::SweepExpiredLocksActivityTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, :admin, company: @company)
    @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)

    Rails.logger.stubs(:info)
  end

  test "deletes only expired Coder lock rows" do
    live = create(
      :integration_data, :workspace_lock, :future_expiry,
      integration: @integration, key: "coder:workspace_lock:live"
    )
    expired = create(
      :integration_data, :workspace_lock, :expired,
      integration: @integration, key: "coder:workspace_lock:expired"
    )
    other_namespace = create(
      :integration_data, :expired,
      integration: @integration, key: "other:thing:1"
    )

    result = run_activity(Activities::Coder::SweepExpiredLocksActivity)

    assert_equal 1, result[:deleted]
    assert IntegrationData.exists?(live.id)
    assert IntegrationData.exists?(other_namespace.id)
    assert_not IntegrationData.exists?(expired.id)
  end

  test "no-ops when there is nothing to sweep" do
    result = run_activity(Activities::Coder::SweepExpiredLocksActivity)
    assert_equal 0, result[:deleted]
  end
end
