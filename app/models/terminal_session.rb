# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  class InvalidStateError < StandardError; end

  include TerminalSessionStateMachine

  WORKFLOW_TIMEOUT = 86_400 # 24 hours

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
    %w[user project session_logs]
  end

  # Scopes
  scope :auth_sessions, -> { where(session_type: "auth_setup") }
  scope :agent_sessions, -> { where(session_type: "agent_session") }
  scope :active, -> { where(state: %w[not_started running ready]) }
  scope :completed, -> { where(state: %w[finished]) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  def active?
    state.in?(%w[not_started running ready])
  end

  def config_files
    session_config["config_files"] || {}
  end

  def env_vars
    session_config["env_vars"] || {}
  end

  # == Workflow ==

  def workflow_id
    "agent-session-#{id}"
  end

  def start_workflow!
    result = TemporalService.start_workflow(
      WorkflowService.container_workflow,
      { session_id: id, manifest: strategy.build_manifest },
      id: workflow_id,
      execution_timeout: WORKFLOW_TIMEOUT
    )
    raise result[:error] unless result[:ok]

    update!(
      temporal_workflow_id: result[:workflow_id],
      temporal_run_id: result[:run_id],
      started_at: Time.current
    )
  end

  def request_finish!
    raise InvalidStateError, "Cannot finish session in state: #{state}" unless may_finish?

    signal_workflow(:container_finished, step_run&.id) if temporal_workflow_id.present?
  end

  def cancel!
    cancel_workflow if temporal_workflow_id.present?
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

  # == Temporal ==

  def signal_workflow(signal_name, payload = nil)
    TemporalService.send_signal(workflow_id, signal_name, payload)
  end

  def signal_workflow_execution_finished
    return unless session_type == "workflow_step"

    sr = step_run
    return unless sr&.workflow_run_id

    execution_workflow_id = "workflow-execution-#{sr.workflow_run_id}"
    TemporalService.send_signal(execution_workflow_id, :container_finished, sr.id)
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] Failed to signal workflow execution for #{id}: #{e.message}")
  end

  def cancel_workflow
    TemporalService.cancel_workflow(workflow_id)
  end

  # == State machine callbacks ==

  def on_started
    start_workflow!
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] Failed to start workflow for #{id}: #{e.message}")
    update!(error_message: "Failed to start workflow: #{e.message}")
    fail!
  end

  def on_ready
    update!(ready_at: Time.current)
  end

  def on_finished
    sync_usage
    update!(finished_at: Time.current, container_id: nil)
    signal_workflow_execution_finished
  end

  def on_failed
    sync_usage
    update!(finished_at: Time.current, container_id: nil)
    signal_workflow_execution_finished
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

  def broadcast_update
    TerminalSessionChannel.broadcast_update(self)
  end
end
