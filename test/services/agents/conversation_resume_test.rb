# frozen_string_literal: true

require "test_helper"

module Agents
  # How each CLI resumes a conversation in a new container, as measured live on staging
  # on 2026-11-20 (research/technical-session-restore-and-sharing-research-2026-11-19.md
  # §3.3). The resume command is the launch command plus the CLI's own flag: a restored
  # session must start with everything a fresh one does.
  class ConversationResumeTest < ActiveSupport::TestCase
    ID = "eb395f2d-d96b-4a6f-ad6c-0ff7c1de7029"

    EXPECTED = {
      "claude_code" => [ %w[.claude/projects], "claude --resume #{ID}" ],
      "codex" => [ %w[.codex/sessions .codex/session_index.jsonl], "resume #{ID}" ],
      "gemini_cli" => [ %w[.gemini/tmp/workspace], "gemini --yolo --resume #{ID}" ],
      "cursor_cli" => [ %w[.cursor/chats], "--resume=#{ID}" ],
      "kiro_cli" => [ %w[.kiro/sessions .kiro/session-index], "--resume-id #{ID}" ],
      "copilot_cli" => [ %w[.copilot/session-state], "--resume=#{ID}" ],
      "grok" => [ %w[.grok/sessions/%2Fworkspace], "--resume #{ID}" ],
      "antigravity_cli" => [ %w[.gemini/antigravity-cli/conversations .gemini/antigravity-cli/brain
                                .gemini/antigravity-cli/cache/last_conversations.json], "--conversation=#{ID}" ]
    }.freeze

    EXPECTED.each do |agent_type, (paths, flag)|
      test "#{agent_type} saves its conversation files and resumes by id" do
        adapter = AgentCredentialsService.for(agent_type).adapter
        command = adapter.resume_command(ID, mode: "interactive")

        assert adapter.resumable?
        assert_equal paths, adapter.conversation_paths
        assert command.start_with?(adapter.session_command(mode: "interactive")), "keeps the launch command: #{command}"
        assert command.end_with?(flag), command
      end
    end

    # Its conversation lives in its home, next to the login the new session writes again.
    test "no conversation path is a login file" do
      EXPECTED.each_key do |agent_type|
        adapter = AgentCredentialsService.for(agent_type).adapter
        adapter.conversation_paths.each do |path|
          refute_match(/credential|token|auth|oauth/i, path, "#{agent_type} would carry its login over: #{path}")
        end
      end
    end

    test "a conversation id is escaped into the command" do
      command = AgentCredentialsService.for("claude_code").adapter.resume_command("a b;rm", mode: "interactive")

      assert_equal "claude --resume a\\ b\\;rm", command
    end

    test "a runtime without a conversation id resumes nothing" do
      assert_nil AgentCredentialsService.for("claude_code").adapter.resume_command(nil, mode: "interactive")
    end
  end
end
