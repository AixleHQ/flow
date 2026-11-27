# frozen_string_literal: true

require "test_helper"

module Coder
  class ApiTest < ActiveSupport::TestCase
    BASE  = "https://coder.example.com"
    TOKEN = "tok-abc"

    setup do
      resolve_hosts_publicly!
    end

    test "verify_token returns a hash on 200" do
      stub_request(:get, "#{BASE}/api/v2/users/me")
        .with(headers: { "Coder-Session-Token" => TOKEN })
        .to_return(
          status: 200,
          body: { id: "u1", username: "alice", email: "alice@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      assert_equal "u1", info[:id]
      assert_equal "alice", info[:username]
    end

    test "verify_token raises HTTPError on non-200" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_return(status: 401)
      err = assert_raises(Coder::Api::HTTPError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
      assert_equal 401, err.status
    end

    test "get_workspace_by_name is nil for a workspace Coder does not know or has deleted" do
      stub_request(:get, "#{BASE}/api/v2/users/me/workspace/w-404").to_return(status: 404, body: "{}")
      stub_request(:get, "#{BASE}/api/v2/users/me/workspace/w-410").to_return(status: 410, body: "{}")

      assert_nil Coder::Api.get_workspace_by_name(coder_url: BASE, session_token: TOKEN, name: "w-404")
      assert_nil Coder::Api.get_workspace_by_name(coder_url: BASE, session_token: TOKEN, name: "w-410")
    end

    test "get_workspace_by_name still raises for any other refusal" do
      stub_request(:get, "#{BASE}/api/v2/users/me/workspace/w-1").to_return(status: 500, body: "{}")

      error = assert_raises(Coder::Api::HTTPError) do
        Coder::Api.get_workspace_by_name(coder_url: BASE, session_token: TOKEN, name: "w-1")
      end
      assert_equal 500, error.status
    end

    test "a refusal that mentions quota raises QuotaRefusedError, a kind of HTTPError" do
      stub_request(:post, "#{BASE}/api/v2/workspaces/u1/builds")
        .to_return(status: 403, body: { message: "Quota exceeded", detail: "used up" }.to_json)

      error = assert_raises(Coder::Api::QuotaRefusedError) do
        Coder::Api.build_workspace(coder_url: BASE, session_token: TOKEN, workspace_id: "u1", transition: "start")
      end
      assert_kind_of Coder::Api::HTTPError, error
      assert_equal "Quota exceeded (used up)", error.explanation
    end

    test "a refusal in a quota status that does not mention quota stays an HTTPError" do
      stub_request(:post, "#{BASE}/api/v2/workspaces/u1/builds")
        .to_return(status: 403, body: { message: "Forbidden" }.to_json)

      error = assert_raises(Coder::Api::HTTPError) do
        Coder::Api.build_workspace(coder_url: BASE, session_token: TOKEN, workspace_id: "u1", transition: "start")
      end
      assert_not_kind_of Coder::Api::QuotaRefusedError, error
    end

    test "list_workspaces returns the workspaces array" do
      stub_request(:get, "#{BASE}/api/v2/workspaces").to_return(
        status: 200,
        body: { workspaces: [ { id: "u1", name: "n1" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = Coder::Api.list_workspaces(coder_url: BASE, session_token: TOKEN)
      assert_equal 1, result.size
      assert_equal "n1", result.first["name"]
    end

    test "build_workspace accepts 200 and 201" do
      stub_request(:post, "#{BASE}/api/v2/workspaces/ws-1/builds").to_return(
        status: 201,
        body: { id: "build-1" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      build = Coder::Api.build_workspace(
        coder_url: BASE, session_token: TOKEN,
        workspace_id: "ws-1", transition: "start"
      )
      assert_equal "build-1", build["id"]
    end

    test "list_templates returns the parsed template list" do
      stub_request(:get, "#{BASE}/api/v2/templates").to_return(
        status: 200,
        body: [ { id: "t1", name: "aws-ec2-spot-v1" } ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

      templates = Coder::Api.list_templates(coder_url: BASE, session_token: TOKEN)
      assert_equal [ "aws-ec2-spot-v1" ], templates.map { |t| t["name"] }
    end

    test "list_templates raises on non-200 instead of reporting an empty catalog" do
      stub_request(:get, "#{BASE}/api/v2/templates").to_return(status: 401)

      error = assert_raises(Coder::Api::HTTPError) do
        Coder::Api.list_templates(coder_url: BASE, session_token: TOKEN)
      end
      assert_equal 401, error.status
      assert_match(/list_templates failed: HTTP 401/, error.message)
    end

    test "ParseError raised on invalid JSON" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_return(
        status: 200, body: "not json",
        headers: { "Content-Type" => "application/json" }
      )

      assert_raises(Coder::Api::ParseError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
    end

    test "TimeoutError raised on Faraday timeout" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_timeout
      assert_raises(Coder::Api::TimeoutError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
    end
  end
end
