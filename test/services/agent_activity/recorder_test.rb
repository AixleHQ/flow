# frozen_string_literal: true

require "test_helper"

module AgentActivity
  class RecorderTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user, settings: { "insights" => { "share_prompts" => true } })
      @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "claude_code")
    end

    test "records prompts and tool calls once, however often a batch arrives" do
      2.times { Recorder.record(@session, prompts: [ prompt("p1", "Fix the login bug") ], tool_calls: [ tool_call("t1") ]) }

      prompt = AgentPrompt.find_by!(terminal_session: @session)
      assert_equal [ "Fix the login bug", 17, false, "p1", "otlp_log" ],
                   [ prompt.text, prompt.text_length, prompt.truncated, prompt.prompt_ref, prompt.source ]
      call = AgentToolCall.find_by!(terminal_session: @session)
      assert_equal [ "Bash", { "command" => "ls" }, true, 12 ], [ call.tool_name, call.arguments, call.success, call.duration_ms ]
      assert call.uid.present?
    end

    test "records nothing for a project that does not share prompts" do
      @project.update!(settings: {})

      assert_equal 0, Recorder.record(@session, prompts: [ prompt("p1", "hello") ], tool_calls: [ tool_call("t1") ])
      assert_not AgentPrompt.exists?(terminal_session: @session)
      assert_not AgentToolCall.exists?(terminal_session: @session)
    end

    test "masks the session's own secrets in prompts, arguments and errors" do
      item = create(:config_item, :secret, scope: @project, name: "API_TOKEN", value: "s3cr3t-value-123")
      @session.config_items << item
      ConfigItemAccess.record!(config_item: item, session: @session, user: @user)

      Recorder.record(@session, prompts: [ prompt("p1", "use s3cr3t-value-123 to call the API") ],
                                tool_calls: [ tool_call("t1", arguments: { "command" => "curl -H 'X: s3cr3t-value-123'" },
                                                              error: "401 for s3cr3t-value-123") ])

      stored = [ AgentPrompt.last.text, AgentToolCall.last.arguments.to_json, AgentToolCall.last.error ].join
      assert_not_includes stored, "s3cr3t-value-123"
    end

    test "caps a long prompt and keeps its full length, and cuts oversized arguments" do
      long = "a" * (Recorder::PROMPT_LIMIT + 10)
      huge = { "content" => "b" * (Recorder::ARGUMENT_STRING_LIMIT * 2) }
      many = { "files" => Array.new(10) { |i| "c#{i}" * (Recorder::ARGUMENT_STRING_LIMIT / 2) } }

      Recorder.record(@session, prompts: [ prompt("p1", long) ],
                                tool_calls: [ tool_call("t1", arguments: huge), tool_call("t2", arguments: many) ])

      prompt = AgentPrompt.last
      assert_equal Recorder::PROMPT_LIMIT, prompt.text.bytesize
      assert_equal long.length, prompt.text_length
      assert prompt.truncated
      calls = AgentToolCall.order(:source_key).to_a
      assert_equal Recorder::ARGUMENT_STRING_LIMIT, calls.first.arguments["content"].bytesize
      assert_equal true, calls.last.arguments["truncated"] # rubocop:disable Minitest/AssertTruthy
    end

    test "names the MCP server of an MCP tool" do
      Recorder.record(@session, tool_calls: [ tool_call("t1", tool_name: "mcp__github__create_issue") ])

      assert_equal "github", AgentToolCall.last.mcp_server
    end

    test "a workflow step's activity carries its run and step" do
      run = create(:workflow_run, project: @project, user: @user)
      step_run = create(:step_run, workflow_run: run)
      step_run.update!(terminal_session: @session)

      Recorder.record(@session.reload, prompts: [ prompt("p1", "Implement the step") ])

      assert_equal [ run.id, step_run.id ], AgentPrompt.last.values_at(:workflow_run_id, :step_run_id)
    end

    test "the initial prompt is recorded for a runtime that reports none" do
      @session.update!(initial_prompt: "Review the pull request", started_at: Time.utc(2026, 11, 11, 9))

      Recorder.record_initial_prompt(@session)

      prompt = AgentPrompt.find_by!(terminal_session: @session)
      assert_equal [ "Review the pull request", "flow", "initial_prompt", Time.utc(2026, 11, 11, 9) ],
                   [ prompt.text, prompt.source, prompt.source_key, prompt.occurred_at ]
    end

    private

    def prompt(id, text)
      Recorder::Prompt.new(key: "prompt:#{id}", occurred_at: Time.current, text: text, prompt_ref: id, source: "otlp_log")
    end

    def tool_call(id, tool_name: "Bash", arguments: { "command" => "ls" }, error: nil)
      Recorder::ToolCall.new(key: "tool:#{id}", occurred_at: Time.current, tool_name: tool_name, arguments: arguments,
                             success: error.nil?, error: error, duration_ms: 12, prompt_ref: "p1", source: "otlp_log")
    end
  end
end
