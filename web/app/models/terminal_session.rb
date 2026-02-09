# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  # State machine
  include TerminalSessionStateMachine

  # Associations
  belongs_to :user
  belongs_to :project, optional: true

  # Callbacks
  before_create :generate_route_token
  before_create :generate_mcp_key
  after_update :broadcast_update

  # Validations
  validates :session_type, presence: true, inclusion: {
    in: %w[auth_setup agent_session tool_setup workflow_step],
    message: "%{value} is not a valid session type"
  }
  validates :agent_type, presence: true, if: -> { session_type.in?(%w[auth_setup agent_session]) }
  validates :agent_type, inclusion: {
    in: %w[claude_code cursor_cli codex gemini_cli],
    message: "%{value} is not a valid agent type"
  }, allow_nil: true
  validates :state, presence: true
  validates :route_token, uniqueness: true, allow_nil: true
  validates :mcp_key, uniqueness: true, allow_nil: true
  validate :validate_session_config

  # Scopes
  scope :auth_sessions, -> { where(session_type: "auth_setup") }
  scope :agent_sessions, -> { where(session_type: "agent_session") }
  scope :active, -> { where(state: %w[not_started started running]) }
  scope :completed, -> { where(state: %w[collected]) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # == session_config accessors ==

  ALLOWED_SESSION_CONFIG_KEYS = %w[config_files env_vars mcp_server_ids tool_ids agent_id skill_ids].freeze

  def config_files
    session_config["config_files"] || {}
  end

  def env_vars
    session_config["env_vars"] || {}
  end

  def mcp_server_ids
    session_config["mcp_server_ids"] || []
  end

  def tool_ids
    session_config["tool_ids"] || []
  end

  def skill_ids
    session_config["skill_ids"] || []
  end

  def configured_agent_id
    session_config["agent_id"]
  end

  # Check if session is active (for MCP authentication)
  def active?
    state.in?(%w[not_started started running])
  end

  # Returns tools available for this session
  # If tool_ids specified in session_config, use those
  # Otherwise, fall back to all enabled custom tools for the project
  def available_tools
    if tool_ids.any?
      Tool.where(id: tool_ids).enabled
    elsif project.present?
      Tool.for_project(project).custom_tools.enabled
    else
      Tool.none
    end
  end

  private

  def generate_route_token
    self.route_token ||= SecureRandom.hex(16)
  end

  def generate_mcp_key
    self.mcp_key ||= SecureRandom.urlsafe_base64(32)
  end

  def validate_session_config
    return if session_config.blank?

    unless session_config.is_a?(Hash)
      errors.add(:session_config, "must be a Hash")
      return
    end

    unknown_keys = session_config.keys - ALLOWED_SESSION_CONFIG_KEYS
    if unknown_keys.any?
      errors.add(:session_config, "contains unknown keys: #{unknown_keys.join(', ')}")
    end
  end

  # Broadcast updates to ActionCable subscribers
  def broadcast_update
    TerminalSessionChannel.broadcast_update(self)
  end
end
