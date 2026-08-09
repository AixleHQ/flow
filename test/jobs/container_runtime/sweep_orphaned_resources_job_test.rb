# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class SweepOrphanedResourcesJobTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @runtime = stub_container_runtime
    end

    teardown do
      cleanup_runtime_overrides
    end

    test "reaps the same objects the scheduled sweep would, and returns its summary" do
      dead = create(:terminal_session, :failed, user: @user, finished_at: 3.hours.ago)
      live = create(:terminal_session, :running, user: @user, started_at: 20.hours.ago)
      @runtime.seed_session_resources(route_token: dead.route_token, created_at: 3.hours.ago)
      live_resources = @runtime.seed_session_resources(route_token: live.route_token, created_at: 20.hours.ago)

      summary = ContainerRuntime::SweepOrphanedResourcesJob.new.perform

      assert_equal 4, summary[:reaped]
      assert_equal 4, summary[:kept_live]
      assert_equal live_resources, @runtime.list_session_resources
    end
  end
end
