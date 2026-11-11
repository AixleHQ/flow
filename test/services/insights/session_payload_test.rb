# frozen_string_literal: true

require "test_helper"

module Insights
  class SessionPayloadTest < ActiveSupport::TestCase
    setup do
      Settings.stubs(:app).returns(OpenStruct.new(version: "1.12.0"))
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "claude_code")
    end

    test "the session's context travels as resource attributes" do
      connect_to_insights!(@project, insights_project_id: "ip-1")
      create(:llm_call, terminal_session: @session)

      resource = attrs(SessionPayload.new(@session).chunks.first["resourceLogs"].first["resource"])

      assert_equal({ "service.name" => "aixle-flow", "service.version" => "1.12.0", "aixle_flow.company.id" => @company.id.to_s,
                     "aixle_flow.project.id" => @project.id.to_s, "aixle_flow.project.name" => @project.name,
                     "aixle_flow.session.id" => @session.id.to_s, "aixle_flow.session.type" => @session.session_type,
                     "aixle_flow.agent.type" => "claude_code", "user.email" => @user.email, "insights.project.id" => "ip-1" },
                   resource)
    end

    test "a call carries its usage, and leaves out what is unknown" do
      call = create(:llm_call, :unknown_cost, terminal_session: @session, model: "gpt-6-sol", provider: "openai",
                                             input_tokens: 90, cache_write_tokens: nil, prompt_ref: "p1")

      record = SessionPayload.new(@session).records.first
      values = attrs(record)

      assert_equal (call.occurred_at.to_r * 1_000_000_000).to_i.to_s, record["timeUnixNano"]
      assert_equal [ "aixle_flow.llm_call", call.uid, "openai", "gpt-6-sol", "90", "unknown", "p1" ],
                   values.values_at("event.name", "aixle_flow.llm_call.id", "gen_ai.provider.name", "gen_ai.request.model",
                                    "aixle_flow.usage.input_tokens", "aixle_flow.cost.basis", "aixle_flow.prompt.ref")
      assert_not values.key?("aixle_flow.cost.usd")
      assert_not values.key?("aixle_flow.usage.cache_write_tokens")
    end

    test "prompts and tool calls are sent only for a project that shares them" do
      create(:llm_call, terminal_session: @session)
      AgentPrompt.create!(terminal_session: @session, source_key: "prompt:p1", source: "otlp_log", occurred_at: 1.minute.ago,
                          text: "Fix the bug", text_length: 11, prompt_ref: "p1")
      AgentToolCall.create!(terminal_session: @session, source_key: "tool:t1", source: "otlp_log", occurred_at: Time.current,
                            tool_name: "Bash", arguments: { "command" => "ls" }, success: true)

      connect_to_insights!(@project, share_prompts: false)
      assert_equal [ "aixle_flow.llm_call" ], names(SessionPayload.new(@session).records)

      connect_to_insights!(@project, share_prompts: true)
      records = SessionPayload.new(@session).records
      prompt = records.find { |r| attrs(r)["event.name"] == "aixle_flow.prompt" }
      tool = records.find { |r| attrs(r)["event.name"] == "aixle_flow.tool_call" }
      assert_equal "Fix the bug", prompt.dig("body", "stringValue")
      assert_equal [ "Bash", { "command" => "ls" }.to_json, true ],
                   [ attrs(tool)["gen_ai.tool.name"], attrs(tool)["aixle_flow.tool.arguments"], attrs(tool)["aixle_flow.tool.success"] ]
    end

    test "records go in chunks, each with the session's context" do
      create_list(:llm_call, 5, terminal_session: @session)

      chunks = SessionPayload.new(@session).chunks(2)

      assert_equal [ 2, 2, 1 ], chunks.map { |c| c["resourceLogs"].first["scopeLogs"].first["logRecords"].size }
      assert(chunks.all? { |c| c["resourceLogs"].size == 1 })
    end

    test "a single repository is named by its remote, without userinfo" do
      create(:repository, scope: @project, clone_url: "https://acme@dev.azure.com/acme/web/_git/web")
      create(:llm_call, terminal_session: @session)

      resource = attrs(SessionPayload.new(@session).chunks.first["resourceLogs"].first["resource"])

      assert_equal "https://dev.azure.com/acme/web/_git/web", resource["vcs.repository.url.full"]
    end

    private

    def attrs(record)
      record["attributes"].to_h { |kv| [ kv["key"], kv["value"].values.first ] }
    end

    def names(records) = records.map { |r| attrs(r)["event.name"] }.uniq
  end
end
