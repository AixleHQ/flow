# frozen_string_literal: true

require "test_helper"

class DataFlow::CheckTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @collect = create(:step, workflow: @workflow, name: "Collect",
      output_asset_specs: [ { "name" => "summary.md", "required" => true } ])
    @analyze = create(:step, workflow: @workflow, name: "Analyze", depends_on_step_ids: [ @collect.id ])
    @report = create(:step, workflow: @workflow, name: "Report", depends_on_step_ids: [ @analyze.id ])
  end

  def issues(**options)
    DataFlow::Check.for_workflow(@workflow.reload, project: @project, **options).issues
  end

  def codes(**options) = issues(**options).map(&:code)

  test "a clean workflow has no issues" do
    @report.update!(instructions: "Summarise {{output:#{@collect.id}:summary.md}}.",
                    input_asset_specs: [ { "name" => "summary.md" } ])

    assert_empty issues
  end

  test "an output two links up is upstream; one that runs later is not, and the fix adds Run after" do
    @collect.update!(instructions: "Compare with {{output:#{@report.id}:final.md}}.")
    @report.update!(output_asset_specs: [ { "name" => "final.md" } ])
    standalone = create(:step, workflow: @workflow, name: "Standalone",
      instructions: "Read {{output:#{@collect.id}:summary.md}}.")

    found = issues.select { |issue| issue.code == "output_not_upstream" }

    assert_equal [ @collect.id.to_s, standalone.id.to_s ], found.map(&:step_key).sort_by(&:to_i)
    cyclic = found.find { |issue| issue.step_key == @collect.id.to_s }
    assert_nil cyclic.fix, "Report runs after Collect, so the edge would close a cycle"
    assert_equal({ kind: "add_dependency", stepKey: @collect.id.to_s },
                 found.find { |issue| issue.step_key == standalone.id.to_s }.fix)
    assert_equal "error", found.first.severity
  end

  test "an output the producer does not declare, and a step that is gone, are errors" do
    gone = create(:step, workflow: @workflow, name: "Gone")
    gone.soft_delete!
    @report.update!(instructions: "{{output:#{@collect.id}:other.md}} {{step:#{gone.id}}} {{asset:nope}}")

    assert_equal %w[output_undeclared ref_missing ref_missing], codes.sort
  end

  test "an asset or server the session does not receive is not attached; attaching it clears the issue" do
    asset = create(:asset, scope: @project, created_by: @user, name: "voice.md")
    server = create(:mcp_server, scope: @project, name: "GitHub")
    @report.update!(instructions: "Use {{asset:#{asset.id}}} and {{mcp:#{server.id}}}.")

    found = issues.select { |issue| issue.code == "ref_not_attached" }
    assert_equal [ { kind: "attach_asset", assetId: asset.id }, { kind: "attach_mcp_server", mcpServerId: server.id } ],
                 found.map(&:fix)

    @report.update!(asset_ids: [ asset.id ])
    @workflow.merge_config!(base_mcp_server_ids: [ server.id ])
    assert_empty issues
  end

  test "everything the project can see counts as attached when the workflow inherits, internal servers included" do
    server = create(:mcp_server, scope: @project, name: "GitHub")
    internal = create(:mcp_server, :internal)
    tool = create(:tool, scope: @project)
    @report.update!(instructions: "Use {{mcp:#{server.id}}}, {{mcp:#{internal.id}}} and {{tool:#{tool.id}}}.")
    @workflow.merge_config!(inherit_all_project_resources: true)

    assert_empty issues
  end

  test "a tool, a skill or a config item the session does not receive is not attached, with the fix to attach it" do
    tool = create(:tool, scope: @project, display_name: "Post summary")
    skill = create(:skill, scope: @project, title: "House style")
    item = create(:config_item, :secret, scope: @project, name: "SLACK_TOKEN")
    @report.update!(instructions: "{{tool:#{tool.id}}} {{skill:#{skill.id}}} {{config_item:#{item.id}}}")

    found = issues
    assert_equal %w[ref_not_attached] * 3, found.map(&:code)
    assert_equal [ { kind: "attach_tool", toolId: tool.id }, { kind: "attach_skill", skillId: skill.id },
                   { kind: "attach_config_item", configItemId: item.id } ], found.map(&:fix)
    assert_includes found.last.message, "references config item SLACK_TOKEN, which is not attached"

    @report.update!(tool_ids: [ tool.id ], skill_ids: [ skill.id ])
    @workflow.merge_config!(base_config_item_ids: [ item.id ])
    assert_empty issues
  end

  test "a config item an attached MCP server names in its headers counts as attached" do
    item = create(:config_item, :secret, scope: @project, name: "GH_TOKEN")
    server = create(:mcp_server, scope: @project, headers: { "Authorization" => "config_item:GH_TOKEN" })
    @report.update!(mcp_server_ids: [ server.id ], instructions: "Authenticate with {{config_item:#{item.id}}}.")

    assert_empty issues
  end

  test "an archived skill or a config item of another project is missing" do
    skill = create(:skill, scope: @project, archived_at: Time.current)
    foreign = create(:config_item, scope: create(:project, :standalone))
    @report.update_column(:instructions, "{{skill:#{skill.id}}} {{config_item:#{foreign.id}}}")

    assert_equal %w[ref_missing ref_missing], codes
  end

  test "an asset of another project or a deleted one is missing, never resolved" do
    other = create(:project, :standalone)
    foreign = create(:asset, scope: other, created_by: @user, name: "secret.md")
    deleted = create(:asset, scope: @project, created_by: @user, name: "old.md", deleted_at: Time.current)
    @report.update_column(:instructions, "{{asset:#{foreign.id}}} {{asset:#{deleted.id}}}")

    found = issues
    assert_equal %w[ref_missing ref_missing], found.map(&:code)
    refute(found.any? { |issue| issue.message.include?("secret.md") })
  end

  test "a session mentioned that does not run before is only a warning" do
    @collect.update!(instructions: "Do not redo what {{step:#{@report.id}}} covers.")

    issue = issues.sole
    assert_equal [ "step_not_upstream", "warning" ], [ issue.code, issue.severity ]
  end

  test "spec names: a path is an error when required, a regex that does not compile too, an empty name is ignored" do
    @analyze.update_columns(
      input_asset_specs: [ { "name" => "/etc/hosts" }, { "name" => "../x.md", "required" => false }, { "name" => "" } ],
      output_asset_specs: [ { "name_pattern" => "*.md" } ]
    )

    found = issues.select { |issue| issue.step_key == @analyze.id.to_s }
    assert_equal [ %w[spec_name_invalid error], %w[spec_name_invalid warning], %w[spec_name_invalid warning],
                   %w[name_pattern_invalid error] ], found.map { |issue| [ issue.code, issue.severity ] }
  end

  test "a required input nothing can provide warns while editing and blocks a run of a first step" do
    first = create(:step, workflow: @workflow, name: "Intake", input_asset_specs: [ { "name" => "brief.md" } ])
    @report.update!(input_asset_specs: [ { "name" => "notes.md" } ])

    editing = issues.select { |issue| issue.code == "input_unsatisfied" }
    assert_equal %w[warning warning], editing.map(&:severity)

    at_run = issues(run_input_asset_ids: []).select { |issue| issue.code == "input_unsatisfied" }
    assert_equal({ first.id.to_s => "error", @report.id.to_s => "warning" }, at_run.to_h { |i| [ i.step_key, i.severity ] })

    picked = create(:asset, scope: @project, created_by: @user, name: "brief.md")
    assert_empty(issues(run_input_asset_ids: [ picked.id ]).select { |issue| issue.step_key == first.id.to_s })
  end

  test "an input matched by an upstream glob output, or by an asset's folder path, is satisfied" do
    @collect.update!(output_asset_specs: [ { "name" => "analysis/**" } ])
    @report.update!(input_asset_specs: [ { "name" => "analysis/domain.md" } ])
    asset = create(:asset, scope: @project, created_by: @user, name: "voice.md", folder: "brand")
    @analyze.update!(asset_ids: [ asset.id ], input_asset_specs: [ { "name" => "brand/voice.md" } ])

    assert_empty issues
  end

  test "two upstream sessions writing the same name warn the session that reads both" do
    @analyze.update!(output_asset_specs: [ { "name" => "summary.md" } ])

    issue = issues.sole
    assert_equal [ "output_collision", @report.id.to_s ], [ issue.code, issue.step_key ]
    assert_includes issue.message, %("Analyze")
  end

  test "braces nothing substitutes are a warning naming them" do
    @report.update!(instructions: "Use {{artifact_name}}.")

    issue = issues.sole
    assert_equal [ "unknown_braces", "{{artifact_name}}" ], [ issue.code, issue.token ]
  end

  test "an unsaved payload is checked by its keys, draft steps included" do
    payload = {
      "steps" => [
        { "id" => @collect.id, "key" => @collect.id.to_s, "name" => "Collect",
          "output_asset_specs" => [ { "name" => "summary.md" } ] },
        { "key" => "new-1", "name" => "Draft", "depends_on_step_ids" => [],
          "instructions" => "Read {{output:#{@collect.id}:summary.md}}." }
      ]
    }

    issue = DataFlow::Check.for_payload(@workflow, payload, project: @project).issues.sole
    assert_equal [ "output_not_upstream", "new-1" ], [ issue.code, issue.step_key ]
    assert_equal({ severity: "error", code: "output_not_upstream", stepKey: "new-1", field: "instructions",
                   message: issue.message, token: "{{output:#{@collect.id}:summary.md}}",
                   fix: { kind: "add_dependency", stepKey: @collect.id.to_s } }, issue.as_json)
  end
end
