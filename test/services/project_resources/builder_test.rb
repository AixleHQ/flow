# frozen_string_literal: true

require "test_helper"

class ProjectResources::BuilderTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    @project = create(:project, company: user.companies.first, owner: user)
    @other_project = create(:project, company: user.companies.first, owner: user)
    @builder = ProjectResources::Builder.new(@project)
  end

  test "creates each resource in the builder's project, ignoring ids and foreign scopes in the attributes" do
    foreign = { id: 999_999, scope_type: "Project", scope_id: @other_project.id }

    agent = @builder.agent!(foreign.merge(name: "architect", title: "Architect", persona: "Designs systems."))
    skill = @builder.skill!(foreign.merge(name: "review", title: "Review", content: "# Review", origin: "manual"))
    server = @builder.mcp_server!(foreign.merge(name: "Sentry", transport: "http", url: "https://mcp.example.com/mcp",
                                                headers: { "X-Org" => "config_item:SENTRY_ORG" }))

    [ agent, skill, server ].each do |resource|
      assert_equal @project, resource.scope
      refute_equal 999_999, resource.id
    end
    assert_equal "manual", skill.origin
    assert_equal 0, skill.install_count
    assert_equal({ "X-Org" => "config_item:SENTRY_ORG" }, server.headers)
  end

  test "creates a tool together with its text files" do
    tool = @builder.tool!(
      { name: "run_tests", display_name: "Run tests", execution_mode: "container",
        docker_image: "ghcr.io/example/runner@sha256:#{'a' * 64}", command: "bash run.sh" },
      files: [ { path: "/workspace/run.sh", content: "echo ok" } ]
    )

    assert_equal @project, tool.scope
    assert_equal [ [ "/workspace/run.sh", "echo ok" ] ], tool.tool_files.map { |f| [ f.path, f.content ] }
  end
end
