# frozen_string_literal: true

require "test_helper"

class SessionQuotaMigrationTest < ActiveSupport::TestCase
  test "quantity conversion preserves CPU milliunits and memory binary units" do
    assert_equal Rational(4), SessionQuotaMigration.quantity("4000m", cpu: true)
    assert_equal 8 * 1024**3, SessionQuotaMigration.quantity("8Gi", cpu: false)
    assert_equal 512 * 1024**2, SessionQuotaMigration.quantity("512Mi", cpu: false)
    assert_equal 2_000_000_000, SessionQuotaMigration.quantity("2G", cpu: false)
    assert_raises(ArgumentError) { SessionQuotaMigration.quantity("unlimited", cpu: false) }
  end

  test "the tightest resource quota determines session capacity" do
    defaults = mock("defaults", cpu_requests: nil, memory_requests: nil, cpu_limits: "4000m", memory_limits: "8Gi", max_pods: 100)
    quota_settings = mock("quota settings", project_defaults: defaults)
    pod_settings = mock("pod settings", runtime_limits_cpu: "1", runtime_limits_memory: "3Gi")
    Settings.stubs(:namespace_resource_quotas).returns(quota_settings)
    Settings.stubs(:kubernetes).returns(pod_settings)
    assert_equal 2, SessionQuotaMigration.capacity("Project", nil)
  end
end
