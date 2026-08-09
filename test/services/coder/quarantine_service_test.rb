# frozen_string_literal: true

require "test_helper"

module Coder
  class QuarantineServiceTest < ActiveSupport::TestCase
    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @service     = Coder::QuarantineService.new(@integration)
    end

    test "marks a workspace and reports the reason back" do
      @service.quarantine(workspace_name: "ws-1", reason: "load average 84.34 over 8.0 (4 cores)")

      assert @service.quarantined?(workspace_name: "ws-1")
      assert_equal "load average 84.34 over 8.0 (4 cores)", @service.reasons["ws-1"]
    end

    test "a quarantine expires on its own so a recovered workspace comes back" do
      @service.quarantine(workspace_name: "ws-1", reason: "unresponsive", minutes: 30)

      travel 31.minutes do
        assert_not @service.quarantined?(workspace_name: "ws-1")
        assert_empty @service.reasons
      end
    end

    test "re-quarantining refreshes the existing row instead of failing on the unique index" do
      @service.quarantine(workspace_name: "ws-1", reason: "first")
      @service.quarantine(workspace_name: "ws-1", reason: "second")

      assert_equal 1, @integration.integration_data.where(key: "coder:workspace_health:ws-1").count
      assert_equal "second", @service.reasons["ws-1"]
    end

    test "clearing removes the marker even after it expired" do
      @service.quarantine(workspace_name: "ws-1", reason: "unresponsive", minutes: -5)

      @service.clear(workspace_name: "ws-1")

      assert_nil @integration.integration_data.find_by(key: "coder:workspace_health:ws-1")
    end

    test "markers are scoped to their integration" do
      other = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @service.quarantine(workspace_name: "ws-1", reason: "unresponsive")

      assert_not Coder::QuarantineService.new(other).quarantined?(workspace_name: "ws-1")
    end
  end
end
