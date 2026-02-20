# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  # State machine
  include TerminalSessionStateMachine

  # Associations
  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :configured_agent, class_name: "Agent", optional: true
  has_one :usage_statistic, dependent: :destroy
  has_many :session_logs, dependent: :destroy
  has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id

  has_and_belongs_to_many :tools, join_table: :session_tools
  has_and_belongs_to_many :skills, join_table: :session_skills
  has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers, class_name: "MCPServer"
  has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets
  has_and_belongs_to_many :repositories, join_table: :session_repositories

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
  validates :mode, inclusion: { in: %w[interactive non_interactive] }, allow_nil: true
  validates :initial_prompt, presence: true, if: -> { mode == "non_interactive" }

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[agent_type project_id session_type state created_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user project]
  end

  # Scopes
  scope :auth_sessions, -> { where(session_type: "auth_setup") }
  scope :agent_sessions, -> { where(session_type: "agent_session") }
  scope :active, -> { where(state: %w[not_started started running]) }
  scope :completed, -> { where(state: %w[collected]) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Dynamic key-value config (config_files, env_vars remain in JSONB)
  def config_files
    session_config["config_files"] || {}
  end

  def env_vars
    session_config["env_vars"] || {}
  end

  def active?
    state.in?(%w[not_started started running])
  end

  # Build the container execution strategy for this session.
  # Resolves strategy class from session_type and initializes with all required params.
  def strategy
    case session_type
    when "auth_setup"
      ContainerStrategies::AgentAuthStrategy.new(**strategy_params)
    when "agent_session"
      ContainerStrategies::AgentSessionStrategy.new(**strategy_params.merge(
        credential: user.agent_credentials.find_by(agent_type: agent_type)
      ))
    else
      raise ArgumentError, "Cannot build strategy for session_type=#{session_type}"
    end
  end

  def available_tools
    if tools.any?
      tools.enabled
    elsif project.present?
      Tool.for_project(project).custom_tools.enabled
    else
      Tool.none
    end
  end

  private

  def strategy_params
    {
      user_id: user_id,
      agent_type: agent_type,
      session_id: id,
      route_token: route_token
    }
  end

  def generate_route_token
    self.route_token ||= SecureRandom.hex(16)
  end

  def generate_mcp_key
    self.mcp_key ||= SecureRandom.urlsafe_base64(32)
  end

  # Broadcast updates to ActionCable subscribers
  def broadcast_update
    TerminalSessionChannel.broadcast_update(self)
  end
end
