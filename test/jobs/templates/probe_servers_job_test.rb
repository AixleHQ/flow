# frozen_string_literal: true

require "test_helper"

class Templates::ProbeServersJobTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    @project = create(:project, company: user.companies.first, owner: user)
    @install = @project.template_installs.create!(installed_by: user, slug: "x", version: 1, commit_sha: "a" * 40,
                                                  package_digest: "d", idempotency_key: "k")
    @server = create(:mcp_server, scope: @project, name: "Hosted", transport: "http", url: "https://mcp.example.com/mcp")
  end

  def probe_returns(status)
    MCP::ToolDriftDetector.stubs(:capture).returns(MCP::ToolDriftDetector::Outcome.new(status: status, drift: {}))
  end

  test "a server that answers 401 switches to OAuth and gets a Connect item" do
    probe_returns(:unauthorized)

    Templates::ProbeServersJob.perform_now(@install.id, [ @server.id ])

    assert_predicate @server.reload, :auth_type_oauth?
    item = @install.setup_items.find_by!(ref: "oauth:#{@server.id}")
    assert_equal [ "oauth", "pending", "Hosted" ], [ item.kind, item.status, item.detail["name"] ]
  end

  test "a failed probe leaves a check-again item, and a re-run updates it instead of adding one" do
    probe_returns(:error)

    2.times { Templates::ProbeServersJob.perform_now(@install.id, [ @server.id ]) }

    assert_equal [ [ "probe", "failed" ] ], @install.setup_items.pluck(:kind, :status)
  end

  test "a reachable public server needs nothing" do
    probe_returns(:ok)

    Templates::ProbeServersJob.perform_now(@install.id, [ @server.id ])

    assert_empty @install.setup_items
  end
end
