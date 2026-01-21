# frozen_string_literal: true

module Api
  module V1
    class OnboardingController < Api::V1::ApplicationController
      # @tags Onboarding
      # @summary Get available agents for selection
      #
      # @response Available agents(200) [Hash{agents: Array<Hash>}]
      def show
        render json: {
          agents: available_agents,
          user_selected: current_user.selected_agents,
          onboarding_completed: current_user.onboarding_completed?
        }
      end

      # @tags Onboarding
      # @summary Complete onboarding with selected agents
      #
      # @request_body Selected agents [!Hash{agents: !Array<String>}]
      # @request_body_example Select agents [Hash] {agents: ["claude_code", "cursor_cli"]}
      #
      # @response Onboarding completed(200) [Hash{message: String}]
      # @response Invalid agents(422) [Hash{error: String}]
      def create
        agents = params[:agents]

        if agents.blank? || !agents.is_a?(Array)
          return render json: { error: "Please select at least one agent" }, status: :unprocessable_entity
        end

        invalid_agents = agents - User::AVAILABLE_AGENTS
        if invalid_agents.any?
          return render json: { error: "Invalid agents: #{invalid_agents.join(', ')}" }, status: :unprocessable_entity
        end

        current_user.complete_onboarding!(agents)

        render json: {
          message: "Onboarding completed",
          selected_agents: current_user.selected_agents,
          next_step: "agent_setup"
        }
      end

      private

      def available_agents
        User::AVAILABLE_AGENTS.map do |agent_type|
          credential = current_user.agent_credential_for(agent_type)
          {
            type: agent_type,
            name: agent_display_name(agent_type),
            description: agent_description(agent_type),
            icon: agent_icon(agent_type),
            configured: credential&.configured? || false,
            selected: current_user.selected_agents.include?(agent_type)
          }
        end
      end

      def agent_display_name(type)
        {
          "codex" => "OpenAI Codex",
          "cursor_cli" => "Cursor CLI",
          "open_code" => "Open Code",
          "claude_code" => "Claude Code"
        }[type] || type.humanize
      end

      def agent_description(type)
        {
          "codex" => "OpenAI's powerful code generation model",
          "cursor_cli" => "AI-powered code editor in your terminal",
          "open_code" => "Open-source AI coding assistant",
          "claude_code" => "Anthropic's Claude for code generation"
        }[type] || ""
      end

      def agent_icon(type)
        {
          "codex" => "🤖",
          "cursor_cli" => "▶️",
          "open_code" => "💻",
          "claude_code" => "🧠"
        }[type] || "⚡"
      end
    end
  end
end
