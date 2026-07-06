# frozen_string_literal: true

require "test_helper"

# Contract pin-test (R4; docs/testing.md §3-§4) for the two Temporal canned seams
# that TemporalHelper hands to callers in place of a real Temporal round-trip:
#
#   * mock_temporal_start           — stands in for TemporalService.start_workflow
#   * mock_workflow_execution_start — stands in for
#                                     TemporalWorkflowRegistry.start_workflow_execution
#
# "A canned return shape (e.g. TemporalHelper's {ok:, workflow_id:, run_id:}) gets
# a pin-test against the real method's shape. A fake without a contract test is a
# mock with better furniture" (R4). These tests pin each helper's canned hash to
# the REAL success return so the seam and reality cannot silently drift apart.
#
# Why we do NOT invoke the real success path here: in Rails.env.test that path
# runs through TemporalService.with_test_environment_handling, which calls
# Temporalio::Testing::WorkflowEnvironment.start_local — booting a real local
# Temporal dev server (test-server binary + gRPC port). It is slow and hangs often
# enough that temporal_service_test.rb stubs start_local in setup just to keep the
# suite moving. The one shortcut that would make a "real" call cheap — stubbing
# Temporalio::Testing itself — is forbidden (R2 + the Phase 2 hard rules). So we
# pin the real shape structurally: the canned side is read at runtime through the
# helper, the real side is pinned to its documented source. Phase 4 (SDK
# time-skipping env) is where the real side becomes a live invocation.
class TemporalHelperContractTest < ActiveSupport::TestCase
  # Real success return of TemporalService.start_workflow, from
  # app/services/temporal_service.rb:
  #   { ok: true, workflow_id: handle.id, run_id: handle.run_id, handle: handle }
  # TemporalWorkflowRegistry.start_workflow_execution returns this hash verbatim —
  # it forwards TemporalService.start_workflow's result unchanged. The
  # "pinned real success keys still appear in source" test below keeps this
  # constant honest against the real method.
  REAL_START_WORKFLOW_SUCCESS_KEYS = %i[ok workflow_id run_id handle].freeze

  test "mock_temporal_start canned shape is success-compatible with the real start_workflow return" do
    mock_temporal_start
    canned = TemporalService.start_workflow(:workflow, :input)

    assert_canned_success_subset(canned, seam: "TemporalHelper#mock_temporal_start")
  end

  test "mock_workflow_execution_start canned shape is success-compatible with the real return" do
    mock_workflow_execution_start
    canned = TemporalWorkflowRegistry.start_workflow_execution(:workflow_run)

    assert_canned_success_subset(canned, seam: "TemporalHelper#mock_workflow_execution_start")
  end

  # :handle is the one real success key the canned seams intentionally omit — no
  # success-path caller consumes it (SessionService reads :ok/:workflow_id/:run_id;
  # WorkflowService and Tool ignore the returned hash). Pin the omission so nobody
  # "fixes" the helper by inventing a fake handle the callers never use.
  test "canned seams omit :handle, the only real success key no caller consumes" do
    mock_temporal_start
    start_canned = TemporalService.start_workflow(:workflow, :input)
    mock_workflow_execution_start
    exec_canned = TemporalWorkflowRegistry.start_workflow_execution(:workflow_run)

    assert_includes REAL_START_WORKFLOW_SUCCESS_KEYS, :handle
    assert_includes REAL_START_WORKFLOW_SUCCESS_KEYS - start_canned.keys, :handle
    assert_includes REAL_START_WORKFLOW_SUCCESS_KEYS - exec_canned.keys, :handle
  end

  # Keep REAL_START_WORKFLOW_SUCCESS_KEYS from rotting into a stale hand-copy:
  # assert the real method still returns each pinned key. A rename on the real
  # side fails here and forces the seam (and its callers) to be revisited.
  test "pinned real success keys still appear in TemporalService#start_workflow source" do
    source = File.read(Rails.root.join("app/services/temporal_service.rb"))
    body = source[/def start_workflow\b.*?(?=\n\s*def )/m]
    assert body, "could not locate TemporalService#start_workflow to pin its return shape"

    assert_includes body, "ok: true"
    (REAL_START_WORKFLOW_SUCCESS_KEYS - [ :ok ]).each do |key|
      assert_includes body, "#{key}:",
        "expected TemporalService#start_workflow to still return #{key}: — " \
        "update REAL_START_WORKFLOW_SUCCESS_KEYS and the callers if the real shape changed"
    end
  end

  private

  def assert_canned_success_subset(canned, seam:)
    assert_kind_of Hash, canned
    assert_equal true, canned[:ok], "#{seam} must model a Temporal success (ok: true)" # rubocop:disable Minitest/AssertTruthy
    assert_includes canned.keys, :workflow_id
    assert_includes canned.keys, :run_id
    assert_kind_of String, canned[:workflow_id]
    assert_kind_of String, canned[:run_id]

    extra = canned.keys - REAL_START_WORKFLOW_SUCCESS_KEYS
    assert_empty extra,
      "#{seam} returns key(s) #{extra.inspect} absent from the real start_workflow success " \
      "shape #{REAL_START_WORKFLOW_SUCCESS_KEYS.inspect}; update the helper (or the constant " \
      "if the real shape changed) to keep the seam honest"
  end
end
