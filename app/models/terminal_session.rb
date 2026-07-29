# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  class InvalidStateError < StandardError; end

  include TerminalSessionStateMachine

  WORKFLOW_TIMEOUT = 86_400 # 24 hours
  BMAD_DEFAULT_MODULES = %w[bmm bmb cis wds].freeze

  # Associations
  belongs_to :user
  belongs_to :project, optional: true
  # Explicit tenant, needed because auth_setup sessions are project-less and
  # create a per-company (billed) agent credential — see SessionCompany.
  belongs_to :company, optional: true
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
  after_commit :broadcast_session_list_update, on: :update

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
  scope :finishing, -> { where(state: "finishing") }
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

  def finishing?
    state == "finishing"
  end

  # Idempotently runs the `start_finishing! → finish!` chain that fires at the
  # tail of every finalization path. Safe to call multiple times: each AASM
  # transition is guarded by its `may_*?` predicate.
  def complete_finish!
    start_finishing! if may_start_finishing?
    finish! if may_finish?
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

  # The session's entitled tool set: explicitly attached tools, the project
  # custom-tool fallback, plus code-defined platform tools whose injection
  # rules match this session (Tools::InjectionRules). Availability
  # (integration gating) is deliberately NOT applied here: serving surfaces
  # filter with Tool#available?(ctx) so tools/call can distinguish
  # entitled-but-disconnected from not-entitled.
  def available_tools(ctx: nil)
    ctx ||= Tools::Context.for_session(self)

    base = tools.enabled.to_a
    if base.none?(&:db_source?) && project.present?
      base += Tool.for_project(project).enabled.to_a
    end

    ctx.candidate_tools = base
    injected = Tools::Registry.injectable.select { |d| d.inject?(ctx) }.map(&:name)
    base += Tool.shadow_rows_for_names(injected).select(&:enabled?)

    base.uniq
  end

  private

  # == State machine callbacks ==

  def on_started
    update!(started_at: Time.current)
  end

  def on_ready
    update!(ready_at: Time.current)
  end

  def on_finishing
    update!(finishing_at: Time.current)
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

  def broadcast_session_list_update
    # Project sessions go to the project's company; project-less sessions go to
    # EVERY company where the user is an active member — matching the listing
    # rule in Web::Company::ApplicationController#company_sessions_scope.
    explicit = company_id || project&.company_id
    company_ids = if explicit
      [ explicit ]
    else
      # Legacy rows only: nothing recorded the tenant, so fall back to every
      # company the user is an active member of (matches the listing rule in
      # Web::Company::ApplicationController#company_sessions_scope).
      user&.company_memberships&.active&.pluck(:company_id) || []
    end
    return if company_ids.empty?

    payload = { type: "session_update", session: TerminalSessionResource.new(self).to_h }
    company_ids.each { |cid| ActionCable.server.broadcast("session_list:company:#{cid}", payload) }
    ActionCable.server.broadcast("session_list:project:#{project_id}", payload) if project_id.present?
  end
end
