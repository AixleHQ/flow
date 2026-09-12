# frozen_string_literal: true

require "test_helper"

# Azure supplies no idempotency key, so "the agent called this twice" and "it
# called once and the answer was lost" are indistinguishable upstream. This row
# is what makes them distinguishable here.
class AzureDevopsOperationTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @payload = { title: "Fix the thing", source_branch: "feature/1" }
  end

  test "the first claim owns the request and a repeat of the same request replays it" do
    record, state = AzureDevopsOperation.claim!(
      integration: @integration, key: "op-1", operation: "create_pull_request", payload: @payload
    )
    assert_equal :claimed, state

    record.succeed!({ id: 42 }, target_kind: "pull_request", target_id: 42)

    replayed, replay_state = AzureDevopsOperation.claim!(
      integration: @integration, key: "op-1", operation: "create_pull_request", payload: @payload
    )
    assert_equal :replayed, replay_state
    assert_equal record.id, replayed.id
    assert_equal 42, replayed.result["id"]
  end

  test "the same key with a different payload is a conflict, not a replay" do
    AzureDevopsOperation.claim!(
      integration: @integration, key: "op-2", operation: "create_pull_request", payload: @payload
    )

    error = assert_raises(AzureDevopsOperation::Conflict) do
      AzureDevopsOperation.claim!(
        integration: @integration, key: "op-2", operation: "create_pull_request",
        payload: @payload.merge(title: "Something else")
      )
    end
    assert_match(/different request/, error.message)
  end

  test "the same key for a different operation is a conflict" do
    AzureDevopsOperation.claim!(
      integration: @integration, key: "op-3", operation: "create_pull_request", payload: @payload
    )

    assert_raises(AzureDevopsOperation::Conflict) do
      AzureDevopsOperation.claim!(
        integration: @integration, key: "op-3", operation: "add_work_item_comment", payload: @payload
      )
    end
  end

  test "the digest ignores key order so a rebuilt payload still replays" do
    AzureDevopsOperation.claim!(
      integration: @integration, key: "op-4", operation: "create_pull_request",
      payload: { a: 1, b: { c: 2, d: 3 } }
    )

    _, state = AzureDevopsOperation.claim!(
      integration: @integration, key: "op-4", operation: "create_pull_request",
      payload: { b: { d: 3, c: 2 }, a: 1 }
    )
    assert_equal :replayed, state
  end

  test "a key is scoped to its integration" do
    other = create(:integration, :azure_devops, :active)

    _, first = AzureDevopsOperation.claim!(
      integration: @integration, key: "shared", operation: "create_pull_request", payload: @payload
    )
    _, second = AzureDevopsOperation.claim!(
      integration: other, key: "shared", operation: "create_pull_request", payload: @payload
    )

    assert_equal :claimed, first
    assert_equal :claimed, second
  end

  test "an unknown outcome is recorded as unknown rather than failed" do
    record, = AzureDevopsOperation.claim!(
      integration: @integration, key: "op-5", operation: "create_pull_request", payload: @payload
    )

    record.unknown!

    assert record.reload.unknown?
    refute_predicate record, :failed?
  end
end
