# frozen_string_literal: true

class TerminalSession < ApplicationRecord
  class InvalidStateError < StandardError; end

  include TerminalSessionStateMachine
  include JsonbDocument
  include CreatedWithinDates
  include RunnerReference

  WORKFLOW_TIMEOUT = 86_400 # 24 hours

  # What the cancellation path reports for every reason a session can be cancelled
  # for — including the ones something already diagnosed precisely: a spend limit read
  # off the terminal by Sessions::Checks::QuotaError, a node that took the pod with it,
  # caught by ScanDeadContainersActivity.
  #
  # Both write the real reason here first and both were then overwritten by this
  # string, because cleanup runs last. That is not only a cosmetic loss: the quota
  # detector in CompleteStepActivity reads `error_message`, so a clobbered session
  # never got `error_category: :quota_exceeded` either, and the run surfaced as a bare
  # "cancelled" with nothing to act on. (2026-09-05: eleven runs, all of them a spend
  # limit nobody could see.)
  # "Session admission is closed" is the queue refusing a permit, which is what
  # a `finish` landing mid-launch looks like from inside an activity. It says
  # nothing about why the work ended, and it used to be both the session's error
  # message and the reason it was marked failed — so a person who pressed Finish
  # four seconds into an authentication session was told their session had
  # failed, in the queue's vocabulary.
  # A launch that was cleaned up before it ever reached a container. It is the
  # queue's own vocabulary, so a real reason already on the session — an expired
  # connection, a revoked credential — outranks it.
  LAUNCH_ABANDONED_ERROR = "Launch abandoned before the container started"

  # What the reconciler says of a session whose container workflow closed under it. It is the
  # queue's own vocabulary too: a reason already on the session (the runner's 15-minute
  # contact loss, for one) outranks it.
  WORKFLOW_ENDED_ERROR = "Container workflow ended"

  GENERIC_ERROR_MESSAGES = [ "Workflow cancelled", "Session admission is closed", LAUNCH_ABANDONED_ERROR, WORKFLOW_ENDED_ERROR ].freeze

  # `suspended` and `restored` end the container as the others do: nothing runs and
  # no slot is held. A suspended session only waits for a person (Sessions::Suspension).
  TERMINAL_STATES = %w[finished failed cancelled suspended restored].freeze
  # The metadata key that marks a session failed by Runners::ContactLoss.
  CONTACT_LOST_KEY = "contact_lost_at"
  private_constant :CONTACT_LOST_KEY
  # A launch that has run its course: the container is up and the session is
  # being used or wound up. `running` is not here, since it is set when the
  # launch starts, before a runner's machine is taken.
  LAUNCHED_STATES = %w[ready finishing].freeze
  # The container is up and in use: running or ready.
  CONTAINER_UP_STATES = %w[running ready].freeze
  # The container is up or being wound up: running, ready or finishing.
  LIVE_STATES = %w[running ready finishing].freeze
  # May still be using its runtime objects (pod, service, route): not_started
  # is in, since the launch creates them; queued is out, as it has none yet.
  USING_RUNTIME_STATES = %w[not_started running ready finishing].freeze
  # Nothing has started yet: not_started or queued.
  WAITING_STATES = %w[not_started queued].freeze
  # The session types that do work, and so count toward usage and are listed:
  # a login (auth_setup) or a tool setup is neither.
  WORK_SESSION_TYPES = %w[agent_session workflow_step].freeze

  # Whether `state` is an end state (finished, failed or cancelled), for a raw
  # value with no record at hand. #ended? calls it.
  def self.ended_state?(state)
    TERMINAL_STATES.include?(state.to_s)
  end

  # Whether `state` is one a launch has got past, for a raw value.
  def self.launched_state?(state)
    LAUNCHED_STATES.include?(state.to_s)
  end

  # Whether `state` is running or ready, for a raw value. #container_up? calls it.
  def self.container_up_state?(state)
    CONTAINER_UP_STATES.include?(state.to_s)
  end

  # Whether `state` is running, ready or finishing, for a raw value. #live? calls it.
  def self.live_state?(state)
    LIVE_STATES.include?(state.to_s)
  end

  # Whether `state` is one that may still use runtime objects, for a raw value.
  # #using_runtime? calls it.
  def self.using_runtime_state?(state)
    USING_RUNTIME_STATES.include?(state.to_s)
  end

  # Whether `state` is not_started or queued, for a raw value. #waiting? calls it.
  def self.waiting_state?(state)
    WAITING_STATES.include?(state.to_s)
  end

  # Whether `session_type` is `auth_setup`, for a raw value (a request param, a
  # context's type). #auth_setup? calls it.
  def self.auth_setup_type?(session_type)
    session_type.to_s == "auth_setup"
  end

  # Whether `session_type` is `workflow_step`, for a raw value. #workflow_step? calls it.
  def self.workflow_step_type?(session_type)
    session_type.to_s == "workflow_step"
  end

  # A specific reason always outranks a generic one, whichever arrives last.
  def self.preferred_error_message(existing, incoming)
    return existing if incoming.blank?
    return existing if existing.present? && GENERIC_ERROR_MESSAGES.include?(incoming)

    incoming
  end

  # `bmm` ships inside the npm package; every other module is cloned from GitHub
  # at install time, and each one costs an api.github.com tag lookup against a
  # per-IP hourly budget shared by the whole cluster (see BmadMethodInjector).
  # `bmb` (builder) and `cis` (creative intelligence suite) are authoring
  # toolkits that pipeline sessions never invoke, so they are no longer installed
  # by default — a session that wants them still names them in
  # `session_config.bmad_modules`.
  BMAD_DEFAULT_MODULES = %w[bmm wds].freeze

  # Associations
  # Optional only for history: a permanently deleted user's sessions stay as the
  # company's record of work, owned by nobody. Every new session has an owner.
  belongs_to :user, optional: true
  validates :user, presence: true, on: :create
  belongs_to :project, optional: true
  # Explicit tenant, needed because auth_setup sessions are project-less and
  # create a per-company (billed) agent credential — see SessionCompany.
  belongs_to :company, optional: true
  belongs_to :configured_agent, class_name: "Agent", optional: true
  # The runner machine the session runs on, assigned by Runners::Machines when
  # its first runtime phase needs one (DESIGN.md §2.4). Kept after the session,
  # as the record of where it ran.
  belongs_to :runner_environment, optional: true
  validate :runner_environment_is_the_runners, if: -> { runner_environment_id && will_save_change_to_runner_environment_id? }
  has_one :usage_statistic, dependent: :destroy
  has_many :insights_otlp_batches, dependent: :delete_all
  has_many :session_logs, dependent: :destroy
  has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id
  has_one :step_run, dependent: :nullify
  has_one :session_checkpoint, dependent: :destroy
  belongs_to :restored_from_session, class_name: "TerminalSession", optional: true
  has_one :restored_session, class_name: "TerminalSession", foreign_key: :restored_from_session_id,
                             inverse_of: :restored_from_session, dependent: :nullify
  before_destroy :retain_unreleased_admission, prepend: true
  has_one :session_admission, dependent: :destroy

  # False for a session without an admission.
  def waiting_for_runner_machine?
    session_admission&.waiting_for_runner_machine? || false
  end

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
  # The integrations this session may use: the ones attached explicitly, those of its
  # repositories and the one it was started from (docs/design/session-integrations.md §3).
  # Tools and gates read this set, never the project's integrations.
  has_and_belongs_to_many :integrations, join_table: :session_integrations

  # Callbacks
  before_create :generate_route_token
  after_create :store_mcp_key_for_older_pods

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
    in: CompanyMembership::AVAILABLE_AGENTS,
    message: "%{value} is not a valid agent type"
  }, allow_nil: true
  validates :state, presence: true
  validates :route_token, uniqueness: true, allow_nil: true
  validates :mode, inclusion: { in: %w[interactive non_interactive] }, allow_nil: true
  validates :initial_prompt, presence: true, if: -> { mode == "non_interactive" }
  validates :requested_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true
  normalizes :reasoning_effort, with: ->(value) { value.to_s.strip.presence }
  # A level needs the session's runtime and an explicitly chosen model, and must be one
  # that runtime takes for that model. A workflow step's session copies its step's
  # runtime, model and level, so it passes the same check.
  validates :reasoning_effort, reasoning_effort: { runtime: :agent_type, model: :requested_model }, on: :create
  # Whatever the container is handed — a repository cloned with its
  # integration's token, an MCP server with its headers, an asset's bytes, a
  # config item's decrypted value — must be this tenant's. Checked on create,
  # where the ids arrive; the readers in SessionContextService scope again.
  { tools: Tool, skills: Skill, mcp_servers: MCPServer, repositories: Repository, input_assets: Asset,
    config_items: ConfigItem, integrations: Integration }.each do |association, model|
    validates association, tenant_ids: { model: model, company: :company }, on: :create
  end
  # What is named explicitly is checked before the integrations derived from repositories and
  # the origin are added (those are added after the save), and is refused, never dropped.
  validate :integrations_are_attachable, on: :create
  before_validation :inherit_project_company
  before_save :inherit_project_company
  validates :company_id, presence: true
  validate :company_is_project_company, if: -> { project && company_id }

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[agent_type project_id session_type state created_at user_id cost_cents total_tokens duration_seconds]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user project session_logs]
  end

  def self.ransackable_scopes(_auth_object = nil)
    %w[created_from created_until]
  end

  # Start to finish. A live session counts up to now, as its list row does; one
  # that never started, or stopped without a finish time, has none.
  DURATION_SECONDS_SQL = <<~SQL.squish
    EXTRACT(EPOCH FROM (COALESCE(terminal_sessions.finished_at,
      CASE WHEN terminal_sessions.state IN ('not_started', 'running', 'ready') THEN NOW() END)
      - terminal_sessions.started_at))
  SQL

  ransacker :duration_seconds, type: :integer do
    Arel.sql(DURATION_SECONDS_SQL)
  end

  # Scopes
  # A session that runs on an external runner.
  scope :on_runner, -> { where.not(runner_id: nil) }
  scope :auth_sessions, -> { where(session_type: "auth_setup") }
  scope :agent_sessions, -> { where(session_type: "agent_session") }
  scope :not_ended, -> { where.not(state: TERMINAL_STATES) }
  scope :ended, -> { where(state: TERMINAL_STATES) }
  # Ended, with no admission that is still unreleased: the container workflow's
  # cleanup, which releases it, will never run (it ended without one, or the
  # admission is gone). A session that failed on contact loss keeps its admission
  # until its cleanup has run, so it is not one.
  scope :cleanup_abandoned, -> { ended.where.not(id: SessionAdmission.unreleased.select(:terminal_session_id)) }
  scope :not_auth_sessions, -> { where.not(session_type: "auth_setup") }
  scope :workflow_steps, -> { where(session_type: "workflow_step") }
  # The container is up and in use: running or ready.
  scope :container_up, -> { where(state: CONTAINER_UP_STATES) }
  # Running, ready or finishing. Not `container_up`, which leaves `finishing` out.
  scope :live, -> { where(state: LIVE_STATES) }
  scope :using_runtime, -> { where(state: USING_RUNTIME_STATES) }
  scope :waiting, -> { where(state: WAITING_STATES) }
  # Sessions that do work: agent sessions and workflow steps.
  scope :work_sessions, -> { where(session_type: WORK_SESSION_TYPES) }
  scope :active, -> { where(state: %w[not_started queued running ready]) }
  scope :finishing, -> { where(state: "finishing") }
  # Waiting for its agent's login to be renewed (Sessions::AuthPause).
  scope :auth_paused, -> { where("terminal_sessions.metadata->>'auth_paused_at' IS NOT NULL") }
  scope :completed, -> { where(state: %w[finished]) }
  scope :suspended, -> { where(state: "suspended") }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  # Sessions `user` may be shown at all: their own, plus every session in a
  # project they can reach. This is only the REACHABILITY half of the rule —
  # the sharing half (`visible_to`, or `visible_to?` per row) still has to be
  # applied. Callers that skip the second half leak other people's shells.
  scope :readable_by, ->(user) {
    # "Their own" still means their own in a company they belong to: a member
    # removed from a company loses its sessions with it.
    member_company_ids = user.company_memberships.active.select(:company_id)
    where(user_id: user.id, company_id: member_company_ids)
      .or(where(project_id: Project.for_user(user).select(:id)))
  }
  # `visible_to?` as SQL, so a list can count and page the sessions a viewer may
  # see instead of filtering a window of rows in Ruby. The two must agree.
  scope :visible_to, ->(viewer) {
    shared = where.not(session_type: "auth_setup")
    where(user_id: viewer.id)
      .or(shared.not_ended.where(user_id: User.where(share_active_sessions: true).select(:id)))
      .or(shared.ended.where(user_id: User.where(share_completed_sessions: true).select(:id)))
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

  # Running or ready. Not `live?`, which includes `finishing`.
  def container_up?
    self.class.container_up_state?(state)
  end

  # Running, ready or finishing.
  def live?
    self.class.live_state?(state)
  end

  # Not started, running, ready or finishing: may still be using its runtime objects.
  def using_runtime?
    self.class.using_runtime_state?(state)
  end

  # Not started or queued: nothing has begun.
  def waiting?
    self.class.waiting_state?(state)
  end

  # Finished, failed or cancelled. Not the opposite of #active?, which leaves `finishing` out.
  def ended?
    self.class.ended_state?(state)
  end

  # Ready or finishing: the launch is over, whether or not a runner's machine holds the session.
  def launched?
    self.class.launched_state?(state)
  end

  # Finished or failed: it ran to its end, and was not cancelled. Not `ended?`.
  def concluded?
    finished? || failed?
  end

  # Failed or cancelled: it ended without finishing.
  def aborted?
    failed? || cancelled?
  end

  # Not started yet, or ended: nothing is running or waiting on it.
  def deletable?
    not_started? || ended?
  end

  def auth_setup?
    self.class.auth_setup_type?(session_type)
  end

  def agent_session?
    session_type == "agent_session"
  end

  # The same question as the `on_runner` scope, for one record.
  def on_runner?
    runner_id.present?
  end

  def workflow_step?
    self.class.workflow_step_type?(session_type)
  end

  # Failed because its runner's machine stopped answering (Runners::ContactLoss).
  # Its machine is not given back until it is heard again.
  def contact_lost?
    metadata.is_a?(Hash) && metadata.key?(CONTACT_LOST_KEY)
  end

  # Marks the session as lost to silence, before it is failed (Runners::ContactLoss).
  def mark_contact_lost!(at)
    merge_jsonb!(:metadata, CONTACT_LOST_KEY => at.iso8601)
  end

  # Takes the mark off a session that was not failed after all.
  def clear_contact_lost!
    remove_jsonb_keys!(:metadata, CONTACT_LOST_KEY)
  end

  # The key the session's container holds for the aixle-tools MCP server. A
  # session launched before keys were derived keeps the random one it was given.
  def mcp_key
    self[:mcp_key].presence || (MCP::SessionKey.generate(self) if persisted?)
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
  #
  # The `visible_to` scope states the same rule in SQL; change both together.
  def visible_to?(viewer)
    return false if viewer.nil?
    return true if user_id == viewer.id
    return false if auth_setup?
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
    return owner_entitled? if user_id == viewer.id

    project.present? && project.accessible_by?(viewer)
  end

  # Whether the session's owner may still act through it: an authenticatable
  # account with an active membership in the session's company. Checked by every
  # gate a running container reaches — the terminal proxy, the MCP key, the
  # credential vending endpoints — so offboarding a member or suspending an
  # account takes effect on sessions already running.
  def owner_entitled?
    return false unless user && User.authenticatable.exists?(id: user_id)

    company_id = SessionCompany.company_id_for(self)
    company_id.present? && CompanyMembership.active.exists?(company_id: company_id, user_id: user_id)
  end

  # The error that ends a session. A stop the person asked for is not a failure, and
  # the queue's own vocabulary is not a diagnosis. `finish` can land while the launch
  # is still running (the next activity then hits a closed permit), so a requested
  # finish keeps whatever real error it already had, and nothing more.
  def ending_error(error)
    return error if error.blank?
    return nil if finishing_at && GENERIC_ERROR_MESSAGES.include?(error)

    error
  end

  # The state the session ends in, given the error `ending_error` returned.
  #
  # A session the person stopped before it was ever usable was cancelled, not
  # finished: closing the dialog on a container that is still coming up is a
  # cancellation, and the only button on that screen says so. `ready_at` is the fact
  # that separates the two: across three days of production, `finishing_at` without
  # `ready_at` described exactly the two authentication sessions this is about and
  # not one workflow step.
  def ending_state(error)
    return "cancelled" if cancelled?
    return "failed" if error || failed?
    return "cancelled" if finishing_at && ready_at.nil?

    "finished"
  end

  def sync_usage
    assign_usage_totals
    save! if changed?
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] Failed to sync usage for #{id}: #{e.message}")
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
  # The step this session worked on. A suspended step's earlier sessions are no longer
  # its current one (StepRun#terminal_session) once it is restored, but each was built
  # for it and says so in its metadata.
  def owning_step_run
    step_run || (StepRun.find_by(id: metadata.to_h["step_run_id"]) if workflow_step?)
  end

  def aixle_builder?
    metadata&.dig("aixle_builder") == true
  end

  # Whether the agent sends its collector everything its telemetry offers — logs and
  # traces with prompts, replies and tool content, and the lifecycle hooks
  # (docs/design/agent-telemetry.md) — rather than only the usage Flow counts. Flow keeps
  # nothing but usage, so only a session of a project exported to Insights gets it: the
  # relay forwards the rest (docs/design/insights-otlp-relay.md).
  def full_telemetry?
    @full_telemetry = project&.exports_to_insights? || false if @full_telemetry.nil?
    @full_telemetry
  end

  # The tools this session is served: the ones attached to it (resolved from its
  # workflow, step or the session itself) plus the plumbing tools whose
  # injection rule matches (docs/design/tool-attachment.md). A session with no
  # custom tool attached gets no custom tool: there is no project-wide fallback.
  def available_tools(ctx: nil)
    ctx ||= Tools::Context.for_session(self)

    base = tools.not_deleted.enabled.where(id: TenantScope.owned(Tool, project: project, company: company || project&.company).select(:id)).to_a

    ctx.candidate_tools = base
    injected = Tools::Registry.injectable.select { |d| d.inject?(ctx) }.map(&:name)
    base += Tool.shadow_rows_for_names(injected).select(&:enabled?)

    base.uniq
  end

  private

  def integrations_are_attachable
    refused = integrations.reject { |integration| Integration::ATTACHABLE_PROVIDERS.include?(integration.provider.to_s) }
    return if refused.empty?

    errors.add(:integrations, "contains integrations of a provider that cannot be attached: #{refused.map(&:id).sort.join(', ')}")
  end

  def runner_project = project

  # RunnerReference: the session's own tenant columns. A session without a
  # project owns no runner, like #runner_project.
  def runner_tenant_ids = project_id ? [ company_id, project_id ] : [ nil, nil ]

  def inherit_project_company
    self.company_id ||= project&.company_id
  end

  def company_is_project_company
    errors.add(:company_id, "must be the project's company") if company_id != project.company_id
  end

  def runner_environment_is_the_runners
    errors.add(:runner_environment, "must be a machine of the session's runner") if runner_environment&.runner_id != runner_id
  end

  # == State machine callbacks ==
  #
  # A transition's `after:` runs before AASM writes the new state, so these only
  # assign: the attributes land in the same save as the state. Nothing that leaves the
  # process is sent from here: Sessions::Lifecycle.transition! sends it, after commit.

  def on_started
    self.started_at = Time.current
  end

  def on_ready
    self.ready_at = Time.current
  end

  def on_queued
    self.queued_at = Time.current
  end

  def on_finishing
    self.finishing_at = Time.current
  end

  # A transition that records an ending the cleanup found (Sessions::Lifecycle.finalize):
  # only assignments. Nothing is sent from here, because finalize wakes nobody.
  def on_ended_by_cleanup
    self.finished_at ||= Time.current
    self.container_id = nil
  end

  def on_finished
    assign_usage_totals
    self.finished_at = Time.current
    self.container_id = nil
  end

  def on_failed
    assign_usage_totals
    self.finished_at = Time.current
    self.container_id = nil
  end

  # The container is still being torn down (by its own workflow), so it keeps
  # its id; the usage it ran up so far is recorded like any other ending.
  def on_cancelled
    assign_usage_totals
    self.finished_at = Time.current
  end

  def assign_usage_totals
    stat = usage_statistic&.reload
    return if stat.nil?

    assign_attributes(
      total_tokens: stat.total_tokens,
      input_tokens: stat.input_tokens,
      output_tokens: stat.output_tokens,
      cache_read_tokens: stat.cache_read_tokens,
      cache_write_tokens: stat.cache_write_tokens,
      cost_cents: stat.cost_cents,
      models: stat.models
    )
  rescue StandardError => e
    Rails.logger.error("[TerminalSession] Failed to read usage for #{id}: #{e.message}")
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

  # Written only so pods still running the previous release, which read the key
  # from this column, can launch and serve a session created by this one. Drop
  # with the column once that release is gone.
  def store_mcp_key_for_older_pods
    update_column(:mcp_key, MCP::SessionKey.generate(self)) if self[:mcp_key].blank?
  end

  # The lists that show this session hear that it changed, and nothing else: one
  # message reaches every subscriber and cannot be redacted per viewer, so each
  # page fetches the row back through its own authorized endpoint. The streams
  # are signed, and only a page that already authorized its viewer hands one out
  # (see #session_list_streams). A dropped update costs a stale row, never the
  # write that caused it.
  def broadcast_session_list_update
    return if company_id.blank? || WORK_SESSION_TYPES.exclude?(session_type)

    session_list_streams.each do |stream|
      InertiaCable.broadcast(stream, { type: "session_update", id: id })
    end
  rescue StandardError => e
    Rails.logger.warn("[TerminalSession] Session-list update for #{id} not sent: #{e.class}: #{e.message}")
  end

  # The company feed, the owner's member page, and the project's Sessions & Runs.
  def session_list_streams
    [ [ company, :sessions ], ([ company, user, :sessions ] if user), ([ project, :sessions_runs ] if project) ].compact
  end
end
