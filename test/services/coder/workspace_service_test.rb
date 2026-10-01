# frozen_string_literal: true

require "test_helper"

module Coder
  class WorkspaceServiceTest < ActiveSupport::TestCase
    setup do
      resolve_hosts_publicly!
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @service     = Coder::WorkspaceService.new(@integration)
      @base        = @integration.coder_url
    end

    def stub_get(path, body, status: 200)
      stub_request(:get, "#{@base}#{path}")
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_post(path, body, status: 201)
      stub_request(:post, "#{@base}#{path}")
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "list returns workspaces filtered by prefix" do
      stub_get("/api/v2/workspaces", {
        workspaces: [
          { id: "u1", name: "aixle-prod-1" },
          { id: "u2", name: "aixle-prod-2" },
          { id: "u3", name: "other" }
        ]
      })

      result = @service.list(prefix: "aixle-prod-")
      assert_equal %w[aixle-prod-1 aixle-prod-2], result.map { |w| w["name"] }
    end

    test "list(own: true) asks Coder only for the token owner's workspaces" do
      own = stub_request(:get, "#{@base}/api/v2/workspaces")
              .with(query: { q: "owner:me" })
              .to_return(status: 200, body: { workspaces: [ { id: "u1", name: "aixle-prod-1" } ] }.to_json,
                         headers: { "Content-Type" => "application/json" })

      result = @service.list(prefix: "aixle-prod-", own: true)

      assert_equal %w[aixle-prod-1], result.map { |w| w["name"] }
      assert_requested own
    end

    test "list raises OperationError on non-200" do
      stub_request(:get, "#{@base}/api/v2/workspaces").to_return(status: 500)
      assert_raises(Coder::WorkspaceService::OperationError) { @service.list }
    end

    test "start returns the build hash" do
      stub_post("/api/v2/workspaces/u1/builds", { id: "build-1", job: { status: "running" } })
      build = @service.start("u1")
      assert_equal "build-1", build["id"]
    end

    # Coder models destruction as a build transition, not an HTTP DELETE.
    test "delete posts a delete-transition build" do
      request = stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds")
                  .with(body: { transition: "delete" }.to_json)
                  .to_return(
                    status: 201,
                    body: { id: "build-del", transition: "delete", job: { status: "pending" } }.to_json,
                    headers: { "Content-Type" => "application/json" }
                  )

      build = @service.delete("u1")

      assert_equal "build-del", build["id"]
      assert_requested request
    end

    test "orphan delete posts an orphaned delete-transition build" do
      request = stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds")
                  .with(body: { transition: "delete", orphan: true }.to_json)
                  .to_return(status: 201, body: { id: "build-del" }.to_json)

      @service.delete("u1", orphan: true)

      assert_requested request
    end

    test "delete raises OperationError when the build is refused" do
      stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds").to_return(status: 409)

      err = assert_raises(Coder::WorkspaceService::OperationError) { @service.delete("u1") }
      assert_match(/build \(delete\) failed/, err.message)
    end

    test "await_build returns when the job succeeds" do
      stub_get("/api/v2/workspacebuilds/build-1", { id: "build-1", job: { status: "succeeded" } })
      build = @service.await_build("build-1", timeout: 1, interval: 0)
      assert_equal "succeeded", build["job"]["status"]
    end

    test "await_build raises on failed job with the provisioner's error" do
      stub_get("/api/v2/workspacebuilds/build-1", {
        id: "build-1", job: { status: "failed", error: "terraform apply: InsufficientInstanceCapacity" }
      })

      err = assert_raises(Coder::WorkspaceService::OperationError) do
        @service.await_build("build-1", timeout: 1, interval: 0)
      end
      assert_equal "build build-1 failed: status=failed — terraform apply: InsufficientInstanceCapacity", err.message
    end

    test "create_workspace failure carries Coder's explanation without the session token" do
      token = @integration.credentials_data["session_token"]
      stub_post("/api/v2/users/#{@integration.coder_user_id}/workspaces",
                { message: "Unable to create workspace.", detail: "rejected token #{token}" }, status: 400)

      err = assert_raises(Coder::WorkspaceService::OperationError) do
        @service.create_workspace(name: "aixle-prod-1", template_id: "tpl-1")
      end

      assert_match(/HTTP 400 — Unable to create workspace\. \(rejected token \[REDACTED\]\)/, err.message)
      assert_no_match(/#{Regexp.escape(token)}/, err.message)
    end

    test "redacts the session token from network error messages" do
      stub_request(:get, "#{@base}/api/v2/workspaces").to_raise(
        Faraday::ConnectionFailed.new("kaboom #{@integration.credentials_data['session_token']}")
      )

      err = assert_raises(Coder::WorkspaceService::OperationError) { @service.list }
      assert_match(/\[REDACTED\]/, err.message)
      assert_no_match(/#{Regexp.escape(@integration.credentials_data['session_token'])}/, err.message)
    end
  end
end
