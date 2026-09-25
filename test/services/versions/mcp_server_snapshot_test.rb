# frozen_string_literal: true

require "test_helper"

class Versions::MCPServerSnapshotTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @actor = Versions::Actor.ui(@user)
    @server = create(:mcp_server, scope: @project, url: "https://mcp.example.com/v1",
                                  headers: { "Authorization" => "Bearer s3cret-token" })
  end

  test "a snapshot names secret keys with a fingerprint and never holds a value" do
    snapshot = Versions::Snapshot.dump(@server)

    assert_equal [ "Authorization" ], snapshot.dig("secrets", "headers").keys
    assert_match(/\Ahmac:\h{16}\z/, snapshot.dig("secrets", "headers", "Authorization"))
    assert_not_includes snapshot.to_json, "s3cret-token"
    assert_equal({}, snapshot.dig("secrets", "env"))
  end

  test "changing a secret value changes its fingerprint, so the diff can say it changed" do
    before = Versions::Snapshot.dump(@server)
    @server.update!(headers: { "Authorization" => "Bearer rotated" })

    assert_not_equal before.dig("secrets", "headers", "Authorization"),
                     Versions::Snapshot.dump(@server).dig("secrets", "headers", "Authorization")
  end

  test "revert keeps the current secret values" do
    Versions.save!(@server, actor: @actor) { @server.update!(description: "first") }
    first = @server.latest_version
    Versions.save!(@server, actor: @actor) do
      @server.update!(description: "second", headers: { "Authorization" => "Bearer rotated" })
    end

    Versions.revert!(@server, to: first, actor: @actor)

    assert_equal "first", @server.reload.description
    assert_equal({ "Authorization" => "Bearer rotated" }, @server.headers)
  end

  test "revert to another destination drops the secrets, as an edit would" do
    Versions.save!(@server, actor: @actor) { @server.update!(description: "old home") }
    old_home = @server.latest_version
    Versions.save!(@server, actor: @actor) do
      @server.update!(url: "https://mcp.example.org/v2", headers: { "Authorization" => "Bearer new-home" })
    end

    Versions.revert!(@server, to: old_home, actor: @actor)

    assert_equal "https://mcp.example.com/v1", @server.reload.url
    assert_equal({}, @server.headers)
  end
end
