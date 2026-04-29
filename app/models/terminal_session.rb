# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  class InvalidStateError < StandardError; end

  include TerminalSessionStateMachine

  WORKFLOW_TIMEOUT = 86_400 # 24 hours
  BMAD_DEFAULT_MODULES = %w[bmm].freeze

  # Associations
  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :configured_agent, class_name: "Agent", optional: true
  has_one :usage_statistic, dependent: :destroy
  has_many :session_logs, dependent: :destroy
  has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id
  has_one :step_run, dependent: :nullify

  has_and_belongs_to_many :tools, join_table: :session_tools
  has_and_belongs_to_many :skills, join_table: :session_skills
  has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers, class_name: "MCPServer"
  has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets
  has_and_belongs_to_many :repositories, join_table: :session_repositories

  # Callbacks
  before_create :generate_route_token
  before_create :generate_mcp_key

  broadcasts_to ->(s) { s }, on: :update
  broadcasts_to ->(s) { s.step_run.workflow_run }, on: :update, if: :step_run

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
  validates :requested_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[agent_type project_id session_type state created_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user project session_logs]
  end

  # Scopes
  scope :auth_sessions, -> { where(session_type: "auth_setup") }
  scope :agent_sessions, -> { where(session_type: "agent_session") }
  scope :active, -> { where(state: %w[not_started running ready]) }
  scope :completed, -> { where(state: %w[finished]) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :with_cached_resource_counts, -> {
    select(
      "terminal_sessions.*",
      "(SELECT COUNT(*) FROM session_logs WHERE session_logs.terminal_session_id = terminal_sessions.id) AS cached_session_logs_count",
      "(SELECT COUNT(*) FROM assets WHERE assets.terminal_session_id = terminal_sessions.id AND assets.status = 'pending_review') AS cached_pending_review_assets_count"
    )
  }

  def active?
    state.in?(%w[not_started running ready])
  end

  def config_files
    session_config["config_files"] || {}
  end

  def env_vars
    session_config["env_vars"] || {}
  end

  def bmad_enabled?
    session_config&.dig("bmad_enabled") == true
  end

  def bmad_modules
    session_config&.dig("bmad_modules") || BMAD_DEFAULT_MODULES
  end

  def workflow_id
    "agent-session-#{id}"
  end

  # == Strategy ==

  def strategy
    case session_type
    when "auth_setup"
      ContainerStrategies::AgentAuthStrategy.new(**strategy_params)
    when "agent_session"
      ContainerStrategies::AgentSessionStrategy.new(**strategy_params.merge(
        credential: user.agent_credentials.find_by(agent_type: agent_type)
      ))
    when "workflow_step"
      ContainerStrategies::WorkflowStepStrategy.new(**strategy_params.merge(
        credential: user.agent_credentials.find_by(agent_type: agent_type)
      ))
    else
      raise ArgumentError, "Cannot build strategy for session_type=#{session_type}"
    end
  end

  def available_tools
    result = []

    if session_type == "workflow_step"
      result += Tool.workflow_tools.enabled.to_a
    end

    result += tools.enabled.to_a

    if result.select(&:custom?).empty? && project.present?
      result += Tool.for_project(project).custom_tools.enabled.to_a
    end

    has_container_tools = result.any? { |t| t.execution_mode.container? }
    if has_container_tools
      result += Tool.internal_tools.enabled.to_a
    end

    if mode == "non_interactive"
      result += Tool.session_lifecycle_tools.to_a
    end

    result.uniq
  end

  private

  # == State machine callbacks ==

  def on_started
    update!(started_at: Time.current)
  end

  def on_ready
    update!(ready_at: Time.current)
  end

  def on_finished
    sync_usage
    update!(finished_at: Time.current, container_id: nil)
  end

  def on_failed
    sync_usage
    update!(finished_at: Time.current, container_id: nil)
    notify_workflow_execution_if_step_session
  end

  def notify_workflow_execution_if_step_session
    return unless session_type == "workflow_step"

    sr = step_run
    return unless sr&.workflow_run_id

    WorkflowService.notify_container_finished(step_run: sr)
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] notify_workflow_execution_if_step_session failed: #{e.message}")
  end

  def sync_usage
    stat = usage_statistic&.reload
    return if stat.nil?

    update!(
      total_tokens: stat.total_tokens,
      input_tokens: stat.input_tokens,
      output_tokens: stat.output_tokens,
      cache_read_tokens: stat.cache_read_tokens,
      cache_write_tokens: stat.cache_write_tokens,
      cost_cents: stat.cost_cents,
      models: stat.models
    )
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] Failed to sync usage for #{id}: #{e.message}")
  end

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
end
