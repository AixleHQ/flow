# frozen_string_literal: true

require "test_helper"

module Coder
  class SweepExpiredLocksJobTest < ActiveSupport::TestCase
    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
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
      no_expiry = create(
        :integration_data, :workspace_lock,
        integration: @integration, key: "coder:workspace_lock:perm"
      )
      other_namespace = create(
        :integration_data, :expired,
        integration: @integration, key: "other:thing:1"
      )

      deleted = Coder::SweepExpiredLocksJob.new.perform

      assert_equal 1, deleted
      assert IntegrationData.exists?(live.id)
      assert IntegrationData.exists?(no_expiry.id)
      assert IntegrationData.exists?(other_namespace.id)
      assert_not IntegrationData.exists?(expired.id)
    end

    test "sweeps across multiple integrations in one call" do
      other = create(:integration, :coder, :active, company: @company, connected_by: @user)
      a_expired = create(
        :integration_data, :workspace_lock, :expired,
        integration: @integration, key: "coder:workspace_lock:a"
      )
      b_expired = create(
        :integration_data, :workspace_lock, :expired,
        integration: other, key: "coder:workspace_lock:b"
      )

      Coder::SweepExpiredLocksJob.new.perform

      assert_not IntegrationData.exists?(a_expired.id)
      assert_not IntegrationData.exists?(b_expired.id)
    end
  end
end
