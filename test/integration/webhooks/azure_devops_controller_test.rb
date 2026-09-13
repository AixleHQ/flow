# frozen_string_literal: true

require "test_helper"

# ActionDispatch::IntegrationTest per docs/testing.md §2 — the legacy
# ActionController::TestCase webhook tests next door are grandfathered.
#
# Azure sends no signature of any kind, so the whole authentication story is the
# subscription's basic-auth password. Copying the GitHub receiver's HMAC
# verification here would have accepted every request.
class Webhooks::AzureDevopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
    @subscription = create(:azure_devops_subscription, integration: @integration, webhook_password: "hook-secret")
  end

  def path(endpoint = @subscription.endpoint_id) = "/webhooks/azure_devops/#{endpoint}"

  def auth(password = "hook-secret")
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("aixle", password) }
  end

  def build_payload(event_id: SecureRandom.uuid, build_id: 4242)
    {
      id: event_id, eventType: "build.complete",
      resource: { id: build_id, status: "completed", result: "succeeded",
                  repository: { id: @repository.external_id } }
    }
  end

  # Shaped from Microsoft's published Service Hooks event reference rather than
  # from what we happen to read, so the fixture would still look like an Azure
  # delivery if the resolver changed its mind about which fields matter.
  # https://learn.microsoft.com/en-us/azure/devops/service-hooks/events
  #
  # The details that are easy to get wrong and are pinned here on purpose:
  # `pullRequestId` is a number, the repository id lives at `repository.id`, and
  # `lastMergeSourceCommit` is an OBJECT carrying `commitId` — not a string.
  def pull_request_payload(event_id: SecureRandom.uuid, event_type: "git.pullrequest.merged",
                           pull_request_id: 813, repository_id: nil)
    {
      subscriptionId: SecureRandom.uuid, notificationId: 3,
      id: event_id, eventType: event_type, publisherId: "tfs",
      message: { text: "Pull request 813 merged" },
      detailedMessage: { text: "Pull request 813 merged" },
      resource: {
        pullRequestId: pull_request_id, status: "completed", mergeStatus: "succeeded",
        sourceRefName: "refs/heads/topic", targetRefName: "refs/heads/main",
        lastMergeSourceCommit: { commitId: "b" * 40 },
        repository: { id: repository_id || @repository.external_id, name: "api",
                      project: { id: @integration.azure_project_id, name: "Customer Platform" } }
      },
      resourceVersion: "1.0-preview.1",
      resourceContainers: { collection: { id: SecureRandom.uuid },
                            account: { id: SecureRandom.uuid },
                            project: { id: @integration.azure_project_id } },
      createdDate: Time.current.utc.iso8601
    }
  end

  # == authentication ==

  test "rejects a delivery with no credentials" do
    post path, params: build_payload, as: :json

    assert_response :unauthorized
  end

  test "rejects a wrong password" do
    post path, params: build_payload, as: :json, headers: auth("not-the-secret")

    assert_response :unauthorized
  end

  test "rejects an unknown endpoint id" do
    post path("nope"), params: build_payload, as: :json, headers: auth

    assert_response :unauthorized
  end

  # The endpoint id appears in Azure's own subscription UI and its failure mails,
  # so knowing one must authorize nothing on its own.
  test "a known endpoint id with a blank password authorizes nothing" do
    post path, params: build_payload, as: :json,
               headers: { "HTTP_AUTHORIZATION" => "Basic #{Base64.strict_encode64('aixle:')}" }

    assert_response :unauthorized
  end

  # == delivery handling ==

  test "accepts a delivery, records it and enqueues the reconciliation" do
    assert_enqueued_with(job: ResolveAzureDevopsEventJob) do
      assert_difference -> { AzureDevopsDelivery.count }, 1 do
        post path, params: build_payload, as: :json, headers: auth
      end
    end

    assert_response :success
    assert @subscription.reload.last_event_at.present?
  end

  # Duplicates are normal, and failing one only earns another redelivery — which
  # pushes the subscription towards probation, where it stops delivering at all.
  test "a redelivered event is acknowledged without being processed twice" do
    payload = build_payload(event_id: "evt-1")
    post path, params: payload, as: :json, headers: auth

    assert_no_enqueued_jobs(only: ResolveAzureDevopsEventJob) do
      assert_no_difference -> { AzureDevopsDelivery.count } do
        post path, params: payload, as: :json, headers: auth
      end
    end

    assert_response :success
  end

  test "the same event id on another subscription is not a duplicate" do
    other = create(:azure_devops_subscription, :pull_request_merged,
                   integration: @integration, webhook_password: "hook-secret")
    post path, params: build_payload(event_id: "shared"), as: :json, headers: auth

    assert_difference -> { AzureDevopsDelivery.count }, 1 do
      post path(other.endpoint_id), params: build_payload(event_id: "shared"), as: :json, headers: auth
    end
  end

  test "an oversized payload is refused rather than parsed" do
    post path, params: build_payload, as: :json,
               headers: auth.merge("CONTENT_LENGTH" => (2 * 1024 * 1024).to_s)

    assert_response :content_too_large
  end

  # Azure retries anything non-2xx forever, so an event we cannot deduplicate is
  # processed rather than dropped; the duplicate risk goes to the log instead.
  # The resolver routes on exactly three fields out of a large delivery —
  # `resource.id` for a build, `resource.pullRequestId` and
  # `resource.repository.id` for a pull request — and re-reads everything else
  # from Azure. Pinned against the documented names, because a rename upstream
  # would make the integration go quiet rather than fail.
  test "a pull request delivery reaches the resolver with the ids it routes on" do
    post path, params: pull_request_payload.to_json,
               headers: auth.merge("CONTENT_TYPE" => "application/json")

    assert_response :ok
    delivered = enqueued_jobs.find { |j| j["job_class"] == "ResolveAzureDevopsEventJob" }["arguments"].first
    assert_equal "git.pullrequest.merged", delivered["event_type"]
    assert_equal 813, delivered["resource"]["pullRequestId"]
    assert_equal @repository.external_id, delivered["resource"]["repository"]["id"]
    assert_equal "b" * 40, delivered["resource"]["lastMergeSourceCommit"]["commitId"]
  end

  test "a resource that is not an object is replaced with an empty one" do
    post path, params: build_payload.merge(resource: "not-an-object").to_json,
               headers: auth.merge("CONTENT_TYPE" => "application/json")

    assert_response :ok
    delivered = enqueued_jobs.find { |j| j["job_class"] == "ResolveAzureDevopsEventJob" }["arguments"].first
    assert_empty delivered["resource"].except("_aj_symbol_keys")
  end

  test "an event with no id is still processed" do
    assert_enqueued_with(job: ResolveAzureDevopsEventJob) do
      post path, params: { eventType: "build.complete", resource: { id: 1 } }, as: :json, headers: auth
    end

    assert_response :success
  end

  test "a delivery brings a probation subscription back to active" do
    @subscription.update!(status: :probation)

    post path, params: build_payload, as: :json, headers: auth

    assert @subscription.reload.active?
  end
end
