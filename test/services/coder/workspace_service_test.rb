# frozen_string_literal: true

require "test_helper"

module Coder
  class WorkspaceServiceTest < ActiveSupport::TestCase
    setup do
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

    test "await_build raises on failed job" do
      stub_get("/api/v2/workspacebuilds/build-1", { id: "build-1", job: { status: "failed" } })
      assert_raises(Coder::WorkspaceService::OperationError) do
        @service.await_build("build-1", timeout: 1, interval: 0)
      end
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
