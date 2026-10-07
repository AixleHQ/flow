# frozen_string_literal: true

require "test_helper"

class InstructionReferences::RendererTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @collect = create(:step, workflow: @workflow, name: "Collect",
      output_asset_specs: [ { "name" => "summary.md", "required" => true } ])
    @report = create(:step, workflow: @workflow, name: "Report", depends_on_step_ids: [ @collect.id ])
  end

  test "each reference becomes the path or name the agent can act on" do
    asset = create(:asset, scope: @project, created_by: @user, name: "voice.md", folder: "brand")
    server = create(:mcp_server, scope: @project, name: "GitHub")
    text = "Read {{asset:#{asset.id}}} and {{output:#{@collect.id}:summary.md}} from {{step:#{@collect.id}}}, " \
           "file issues with {{mcp:#{server.id}}}."

    rendered = InstructionReferences::Renderer.new(step: @report, project: @project).render(text)

    assert_equal "Read `/workspace/assets/brand/voice.md` and `/workspace/assets/summary.md` from " \
                 "session \"Collect\", file issues with the \"GitHub\" MCP server.", rendered
  end

  test "a step's own output is where it writes, not where later steps read" do
    rendered = InstructionReferences::Renderer.new(step: @collect, project: @project)
                                              .render("Write {{output:#{@collect.id}:summary.md}}.")

    assert_equal "Write `/workspace/outputs/summary.md`.", rendered
  end

  test "an id outside the project, a deleted step or an undeclared output renders as missing" do
    other_project = create(:project, :standalone)
    foreign = create(:asset, scope: other_project, created_by: @user, name: "secret.md")
    gone = create(:step, workflow: @workflow, name: "Gone")
    gone.soft_delete!
    text = "{{asset:#{foreign.id}}} {{step:#{gone.id}}} {{output:#{@collect.id}:other.md}}"

    rendered = InstructionReferences::Renderer.new(step: @report, project: @project).render(text)

    assert_equal "[missing reference: asset:#{foreign.id}] [missing reference: step:#{gone.id}] " \
                 "[missing reference: output:#{@collect.id}:other.md]", rendered
    refute_includes rendered, "secret.md"
  end

  test "text without references comes back untouched" do
    text = "Plain {{artifact_name}} text"

    assert_same text, InstructionReferences::Renderer.new(step: @report, project: @project).render(text)
  end
end
