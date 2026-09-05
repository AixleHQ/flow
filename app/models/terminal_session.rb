# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  class InvalidStateError < StandardError; end

  include TerminalSessionStateMachine

  WORKFLOW_TIMEOUT = 86_400 # 24 hours

  # `bmm` ships inside the npm package; every other module is cloned from GitHub
  # at install time, and each one costs an api.github.com tag lookup against a
  # per-IP hourly budget shared by the whole cluster (see BmadMethodInjector).
  # `bmb` (builder) and `cis` (creative intelligence suite) are authoring
  # toolkits that pipeline sessions never invoke, so they are no longer installed
  # by default — a session that wants them still names them in
  # `session_config.bmad_modules`.
  BMAD_DEFAULT_MODULES = %w[bmm wds].freeze

  # Serialized keys (camelCase, as ApplicationResource emits them) stripped from
  # the session-list broadcast — see #broadcast_session_list_update.
  BROADCAST_REDACTED_KEYS = %w[initialPrompt metadata contextMetadata].freeze

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
  before_destroy :retain_unreleased_admission, prepend: true
  has_one :session_admission, dependent: :destroy

  def retain_unreleased_admission
    if session_admission && !session_admission.released_at
      errors.add(:base, "Session runtime cleanup is still pending")
      throw :abort
    end
  end

  has_and_belongs_to_many :tools, join_table: :session_tools
  has_and_belongs_to_many :skills, join_table: :session_skills
  has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers, class_name: "MCPServer"
  has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets
  has_and_belongs_to_many :repositories, join_table: :session_repositories
  # Attaching a config item is what authorizes this session to decrypt its value
  # through `get_config_item` — the tool resolves against this set, never against
  # the project's items. See docs/implementation-artifacts/spec-session-config-item-access.md.
  has_and_belongs_to_many :config_items, join_table: :session_config_items

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
    in: %w[claude_code cursor_cli codex gemini_cli grok],
    message: "%{value} is not a valid agent type"
  }, allow_nil: true
  validates :state, presence: true
  validates :route_token, uniqueness: true, allow_nil: true
  validates :mcp_key, uniqueness: true, allow_nil: true
  validates :mode, inclusion: { in: %w[interactive non_interactive] }, allow_nil: true
  validates :initial_prompt, presence: true, if: -> { mode == "non_interactive" }
  validates :requested_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true
  validate :config_items_belong_to_project

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
  scope :active, -> { where(state: %w[not_started queued running ready]) }
  scope :finishing, -> { where(state: "finishing") }
  scope :completed, -> { where(state: %w[finished]) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  # Sessions `user` may be shown at all: their own, plus every session in a
  # project they can reach. This is only the REACHABILITY half of the rule —
  # `visible_to?` still has to be applied per row, because whether a session is
  # shared depends on its type and lifecycle phase rather than on anything SQL
  # can select. Callers that skip the second half leak other people's shells.
  scope :readable_by, ->(user) {
    where(user_id: user.id).or(where(project_id: Project.for_user(user).select(:id)))
  }
  scope :with_cached_resource_counts, -> {
    select(
      "terminal_sessions.*",
      "(SELECT COUNT(*) FROM session_logs WHERE session_logs.terminal_session_id = terminal_sessions.id) AS cached_session_logs_count",
      "(SELECT COUNT(*) FROM assets WHERE assets.terminal_session_id = terminal_sessions.id AND assets.status = 'pending_review') AS cached_pending_review_assets_count"
    )
  }

  def active?
    state.in?(%w[not_started queued running ready])
  end

  def finishing?
    state == "finishing"
  end

  # May `viewer` open this session — its live terminal/editor while it runs, or
  # its replayed log once it is over?
  #
  # This is a SECOND gate, on top of the project/company scoping every session
  # screen already applies: reaching the record is not the same as being allowed
  # to watch the person work. The owner always passes; for everyone else the
  # owner's profile preferences decide, per lifecycle phase, and no role
  # overrides them — a company admin reads the same two booleans, because the
  # setting exists precisely to keep other people out of a live shell.
  #
  # Two session types are not personal work and are exempt:
  #   - workflow_step — team automation, watched from the workflow run screen;
  #     gating it would hide a shared pipeline behind whoever happened to
  #     trigger it.
  #   - auth_setup — the owner's credential login, never anyone else's business,
  #     so it is owner-only regardless of preferences.
  def visible_to?(viewer)
    return false if viewer.nil?
    return true if user_id == viewer.id
    return true if session_type == "workflow_step"
    return false if session_type == "auth_setup"
    return false if user.nil?

    active? || finishing? ? user.share_active_sessions? : user.share_completed_sessions?
  end

  # May `viewer` reach the CONTAINER's routes (ttyd, the IDE, the file server)?
  #
  # Asked by the Traefik ForwardAuth endpoint (Api::V1::Internal::WsAuth), which
  # sees only a route token and a session cookie — it has no scoped query behind
  # it, so the reachability half that a web screen gets for free from
  # `current_project.terminal_sessions` has to be stated here. Both halves must
  # hold: the viewer can reach the session's project, AND the owner shares this
  # phase of it.
  #
  # NOTE: ttyd runs writable (`-W`) and the IDE is a full VS Code, so passing
  # this grants the viewer an interactive shell in the container, not a
  # read-only window.
  def container_accessible_by?(viewer)
    return false if queued? || cancelled?
    return false unless visible_to?(viewer)
    return true if user_id == viewer.id

    project.present? && project.accessible_by?(viewer)
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
      ContainerStrategies::AgentSessionStrategy.new(**strategy_params.merge(credential: session_credential))
    when "workflow_step"
      ContainerStrategies::WorkflowStepStrategy.new(**strategy_params.merge(credential: session_credential))
    else
      raise ArgumentError, "Cannot build strategy for session_type=#{session_type}"
    end
  end

  # The credential this session's container may use: the acting user's, in THIS
  # session's company. Never `user.agent_credentials` — a person holds one credential
  # per company, so an unscoped read hands a container another tenant's tokens (and
  # bills that tenant for the tokens it spends).
  def session_credential
    SessionCompany.agent_credentials_for(self).find_by(agent_type: agent_type)
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

  # Attaching a config item is what lets this session decrypt its value, so the
  # ids cannot be taken on trust from whoever posted them: a session may only
  # attach config items of its OWN project. Enforced on the model rather than in
  # a controller so every path — the API, the meta tools, a console — is covered.
  def config_items_belong_to_project
    return if config_items.empty?

    if project_id.blank?
      errors.add(:config_items, "cannot be attached to a session without a project")
      return
    end

    foreign = config_items.reject { |item| item.scope_type == "Project" && item.scope_id == project_id }
    return if foreign.empty?

    errors.add(:config_items, "must belong to this session's project: #{foreign.map(&:name).sort.join(', ')}")
  end

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

    # One payload fans out to every listener on the company/project channel, so
    # it cannot be redacted per viewer the way a page render can. What the list
    # rows never display — the prompt and the metadata blobs, i.e. what the
    # person is working on — is therefore dropped outright rather than pushed at
    # everyone in the company. The route token and its URLs stay: they are gated
    # at the proxy (Api::V1::Internal::WsAuth), not by being kept quiet.
    session_payload = TerminalSessionResource.new(self).to_h.except(*BROADCAST_REDACTED_KEYS)
    payload = { type: "session_update", session: session_payload }
    company_ids.each { |cid| ActionCable.server.broadcast("session_list:company:#{cid}", payload) }
    ActionCable.server.broadcast("session_list:project:#{project_id}", payload) if project_id.present?
  end
end
