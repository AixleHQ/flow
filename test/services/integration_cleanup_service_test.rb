# frozen_string_literal: true

require "test_helper"

class IntegrationCleanupServiceTest < ActiveSupport::TestCase
  test "calls every provider hook with the given session" do
    session = OpenStruct.new(id: "s", project: nil)

    original = IntegrationCleanupService::PROVIDER_HOOKS
    called   = []
    fake_hooks = [ ->(s) { called << [ :a, s.id ] }, ->(s) { called << [ :b, s.id ] } ]

    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, fake_hooks)

    IntegrationCleanupService.release_session_locks!(session)

    assert_equal [ [ :a, "s" ], [ :b, "s" ] ], called
  ensure
    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, original)
  end

  test "swallows hook exceptions and continues" do
    original = IntegrationCleanupService::PROVIDER_HOOKS
    called   = []
    fake_hooks = [
      ->(_) { raise "boom" },
      ->(_) { called << :ok }
    ]

    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, fake_hooks)

    assert_nothing_raised do
      IntegrationCleanupService.release_session_locks!(OpenStruct.new(id: "s"))
    end
    assert_equal [ :ok ], called
  ensure
    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, original)
  end

  test "returns early on nil session without invoking hooks" do
    original = IntegrationCleanupService::PROVIDER_HOOKS
    called   = []
    fake_hooks = [ ->(_) { called << :hit } ]

    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, fake_hooks)

    IntegrationCleanupService.release_session_locks!(nil)

    assert_empty called
  ensure
    IntegrationCleanupService.send(:remove_const, :PROVIDER_HOOKS)
    IntegrationCleanupService.const_set(:PROVIDER_HOOKS, original)
  end
end
