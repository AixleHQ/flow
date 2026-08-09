# frozen_string_literal: true

require "test_helper"

module Activities
  module Container
    class SweepOrphanedResourcesActivityTest < ActiveSupport::TestCase
      OLD = 3.hours
      FRESH = 1.minute

      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @runtime = stub_container_runtime
      end

      teardown do
        cleanup_runtime_overrides
      end

      # == The leak this exists for ==

      test "reaps every object of a session that no longer has a row" do
        resources = @runtime.seed_session_resources(route_token: SecureRandom.hex(16), created_at: OLD.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 4, result[:reaped]
        assert_equal 1, result[:sessions]
        assert_equal 0, result[:failed]
        assert_equal({ "IngressRoute" => 1, "Middleware" => 1, "Service" => 1, "Pod" => 1 }, result[:by_kind])
        assert_equal resources, @runtime.deleted_session_resources
        assert_empty @runtime.list_session_resources
      end

      test "reaps objects in routing-first order so traffic never points at a vanishing backend" do
        @runtime.seed_session_resources(route_token: SecureRandom.hex(16), created_at: OLD.ago)

        run_activity(SweepOrphanedResourcesActivity)

        assert_equal %w[IngressRoute Middleware Service Pod],
                     @runtime.deleted_session_resources.map(&:kind)
      end

      test "reaps objects of a session that failed long ago" do
        session = create(:terminal_session, :failed, user: @user, finished_at: OLD.ago)
        @runtime.seed_session_resources(route_token: session.route_token, created_at: OLD.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 4, result[:reaped]
        assert_equal 0, result[:kept_live]
      end

      test "reaps objects of a session that finished long ago" do
        session = create(:terminal_session, user: @user, state: "finished", finished_at: OLD.ago)
        @runtime.seed_session_resources(route_token: session.route_token, created_at: OLD.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 4, result[:reaped]
      end

      # == Safety: a live session is never touched ==

      test "never reaps the objects of a live session, however old they are" do
        %w[not_started running ready finishing].each do |state|
          session = create(:terminal_session, user: @user, state: state, started_at: 20.hours.ago)
          @runtime.seed_session_resources(route_token: session.route_token, created_at: 20.hours.ago)
        end

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 16, result[:kept_live]
        assert_empty @runtime.deleted_session_resources
        assert_equal 16, @runtime.list_session_resources.size
      end

      test "never reaps objects created inside the minimum-age window" do
        @runtime.seed_session_resources(route_token: SecureRandom.hex(16), created_at: FRESH.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 4, result[:kept_recent]
        assert_empty @runtime.deleted_session_resources
      end

      test "never reaps objects of a session that finished inside the minimum-age window" do
        session = create(:terminal_session, user: @user, state: "finished", finished_at: FRESH.ago)
        @runtime.seed_session_resources(route_token: session.route_token, created_at: OLD.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 4, result[:kept_finalizing]
        assert_equal 0, result[:kept_live]
        assert_empty @runtime.deleted_session_resources
      end

      test "never reaps an object whose owner cannot be established" do
        @runtime.seed_session_resources(route_token: nil, created_at: OLD.ago, kinds: %w[Pod])

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 1, result[:kept_unowned]
        assert_empty @runtime.deleted_session_resources
      end

      test "never reaps an object whose age the runtime cannot report" do
        @runtime.seed_session_resources(route_token: SecureRandom.hex(16), created_at: nil)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 4, result[:kept_recent]
        assert_empty @runtime.deleted_session_resources
      end

      test "reaps the dead session's objects while leaving the live one's alone" do
        live = create(:terminal_session, :running, user: @user, started_at: 20.hours.ago)
        dead = create(:terminal_session, :failed, user: @user, finished_at: OLD.ago)
        live_resources = @runtime.seed_session_resources(route_token: live.route_token, created_at: 20.hours.ago)
        @runtime.seed_session_resources(route_token: dead.route_token, created_at: OLD.ago)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 4, result[:reaped]
        assert_equal 4, result[:kept_live]
        assert_equal [ dead.route_token ], @runtime.deleted_session_resources.map(&:route_token).uniq
        assert_equal live_resources, @runtime.list_session_resources
      end

      # == Diagnosability ==

      test "counts objects the runtime refused to delete instead of reporting them reaped" do
        resources = @runtime.seed_session_resources(route_token: SecureRandom.hex(16), created_at: OLD.ago)
        @runtime.fail_session_resource_delete(resources.first.name)

        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 3, result[:reaped]
        assert_equal 1, result[:failed]
        assert_equal [ resources.first ], @runtime.list_session_resources
      end

      test "reports an all-zero summary when the runtime holds nothing" do
        result = run_activity(SweepOrphanedResourcesActivity)

        assert_equal 0, result[:reaped]
        assert_equal 0, result[:sessions]
        assert_equal 0, result[:kept_live]
        assert_equal 0, result[:kept_finalizing]
        assert_equal 0, result[:kept_recent]
        assert_equal 0, result[:kept_unowned]
        assert_equal 0, result[:failed]
        assert_empty result[:by_kind]
      end
    end
  end
end
