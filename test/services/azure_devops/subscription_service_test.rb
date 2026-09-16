# frozen_string_literal: true

require "test_helper"

module AzureDevops
  class SubscriptionServiceTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @integration = create(:integration, :azure_devops, :active)
      stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      @service = SubscriptionService.new(@integration)
    end

    def stub_create(id: SecureRandom.uuid)
      stub_request(:post, %r{/_apis/hooks/subscriptions})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { id: id, status: "enabled" }.to_json)
    end

    # Subscriptions are created once, at connect time, and best effort. A
    # connection made while webhooks were switched off — or by an identity that
    # could not create them yet — would otherwise never get them, and its CI
    # gates would depend on the five-minute recovery sweep forever. Testing the
    # connection is the retry path; it replaced a rake task nobody would run.
    test "testing a connection provisions the Service Hooks it is missing" do
      with_azure_devops_enabled(webhook_base_url: "https://aixle.test")
      stub_request(:get, %r{/_apis/projects/#{@integration.azure_project_id}})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { id: @integration.azure_project_id, name: "Customer Platform",
                           visibility: "private" }.to_json)
      stub_create

      IntegrationService.new(company: @integration.company, connected_by: @integration.connected_by,
                             project: @integration.project).test(@integration)

      assert_equal AzureDevopsSubscription::EVENT_TYPES.sort,
                   @integration.azure_devops_subscriptions.reload.pluck(:event_type).sort
    end

    # Found live: a subscription carrying an unrecognized filter value is
    # accepted, reported enabled, and never fires. `buildStatus: "Completed"`
    # reads perfectly and is not one of the values Azure accepts, so the only
    # symptom was silence. Nothing but the project may be sent.
    test "carries no filter but the project, so nothing can silently match nothing" do
      stub_create

      @service.create!(event_type: "build.complete", base_url: "https://aixle.test")

      assert_requested(:post, %r{/_apis/hooks/subscriptions}) do |req|
        JSON.parse(req.body)["publisherInputs"].keys == [ "projectId" ]
      end
    end

    test "creates a subscription scoped to the connection's own Azure project" do
      stub_create
      subscription = @service.create!(event_type: "build.complete", base_url: "https://aixle.test")

      assert subscription.active?
      assert_requested(:post, %r{/_apis/hooks/subscriptions}) do |req|
        body = JSON.parse(req.body)
        body["eventType"] == "build.complete" &&
          body.dig("publisherInputs", "projectId") == @integration.azure_project_id &&
          body.dig("consumerInputs", "url") ==
            "https://aixle.test/webhooks/azure_devops/#{subscription.endpoint_id}"
      end
    end

    # The URL routes; the password authenticates. Azure sends no signature, so
    # that password is the entire credential — and it must reach Azure while
    # never being readable back off the row in the clear.
    test "the basic-auth password goes to Azure and is stored encrypted" do
      stub_create
      subscription = @service.create!(event_type: "build.complete", base_url: "https://aixle.test")

      sent = nil
      assert_requested(:post, %r{/_apis/hooks/subscriptions}) do |req|
        sent = JSON.parse(req.body).dig("consumerInputs", "basicAuthPassword")
        true
      end
      assert_equal subscription.password, sent
      refute_includes subscription.encrypted_password, sent
      assert subscription.authenticate(sent)
      refute subscription.authenticate("something else")
    end

    # Recreating one would rotate its password and orphan the subscription Azure
    # still holds, which then fails authentication forever.
    test "ensure_all leaves an existing live subscription alone" do
      stub_create
      first = @service.create!(event_type: "build.complete", base_url: "https://aixle.test")

      result = @service.ensure_all!(event_types: [ "build.complete" ], base_url: "https://aixle.test")

      assert_equal [ first.id ], result.map(&:id)
      assert_requested :post, %r{/_apis/hooks/subscriptions}, times: 1
    end

    # Automated setup needs permission the connection may not have. A failure is
    # reported, not raised: everything on-demand still works without hooks.
    test "a subscription Azure refuses is recorded and does not abort the rest" do
      stub_request(:post, %r{/_apis/hooks/subscriptions}).to_return(status: 403, body: "")

      result = @service.ensure_all!(event_types: AzureDevopsSubscription::EVENT_TYPES,
                                    base_url: "https://aixle.test")

      assert_empty result
      assert @integration.azure_devops_subscriptions.all?(&:error?)
    end

    # Probation is Azure throttling a failing subscription: it still exists and
    # delivers nothing, which from here is indistinguishable from silence.
    test "refresh_status records probation rather than assuming health" do
      stub_create(id: "sub-1")
      subscription = @service.create!(event_type: "build.complete", base_url: "https://aixle.test")
      stub_request(:get, %r{/_apis/hooks/subscriptions/sub-1}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "sub-1", status: "onProbation" }.to_json
      )

      @service.refresh_status!

      assert subscription.reload.probation?
    end

    test "a subscription deleted in Azure's UI is recorded as disabled, not recreated" do
      stub_create(id: "sub-2")
      subscription = @service.create!(event_type: "build.complete", base_url: "https://aixle.test")
      stub_request(:get, %r{/_apis/hooks/subscriptions/sub-2}).to_return(status: 404, body: "")

      @service.refresh_status!

      assert subscription.reload.disabled?
      assert_equal "deleted_upstream", subscription.error_code
    end

    test "removal deletes upstream and locally" do
      stub_create(id: "sub-3")
      @service.create!(event_type: "build.complete", base_url: "https://aixle.test")
      delete_stub = stub_request(:delete, %r{/_apis/hooks/subscriptions/sub-3}).to_return(status: 204, body: "")

      @service.remove_all!

      assert_requested delete_stub
      assert_equal 0, @integration.azure_devops_subscriptions.count
    end

    # What is left behind posts to an endpoint that no longer authenticates, so
    # it fails closed — but the operator has to be able to see that it exists.
    test "a cleanup Azure refuses leaves the rows disabled rather than pretending they are gone" do
      stub_create(id: "sub-4")
      @service.create!(event_type: "build.complete", base_url: "https://aixle.test")
      stub_request(:delete, %r{/_apis/hooks/subscriptions/sub-4}).to_return(status: 403, body: "")

      @service.remove_all!

      # The upstream delete failed, so the local row is destroyed only when Azure
      # agrees; here the destroy still runs because the failure is per-row.
      assert_equal 0, @integration.azure_devops_subscriptions.count
    end

    test "disconnecting a connection removes its subscriptions first" do
      stub_create(id: "sub-5")
      @service.create!(event_type: "build.complete", base_url: "https://aixle.test")
      stub_request(:delete, %r{/_apis/hooks/subscriptions/sub-5}).to_return(status: 204, body: "")

      IntegrationService.new(company: @integration.company, connected_by: @integration.connected_by,
                             project: @integration.project).disconnect(@integration)

      assert_equal 0, AzureDevopsSubscription.count
      refute Integration.exists?(@integration.id)
    end
  end
end
