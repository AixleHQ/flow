# frozen_string_literal: true

class CompanyMembership < ApplicationRecord
  extend Enumerize

  # State machine (invited -> active, suspend/reactivate, revoke)
  include CompanyMembershipStateMachine

  # Onboarding answers live per membership: a person can hold a different role
  # in each company, pick different agents, and MUST authenticate a separate
  # agent credential per company so vendor spend is billed to the company that
  # incurred it.
  AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
  POSITIONS = %w[qa pm_po_ba dev designer cto other].freeze
  AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli antigravity_cli grok].freeze

  # Associations
  belongs_to :user
  belongs_to :company
  belongs_to :invited_by, class_name: "User", optional: true
  belongs_to :default_agent_credential, class_name: "AgentCredential", optional: true

  # This member's credentials IN THIS COMPANY. Deliberately keyed on both ids —
  # the same user has a different credential per company.
  has_many :agent_credentials,
           ->(membership) { where(company_id: membership.company_id) },
           foreign_key: :user_id, primary_key: :user_id,
           inverse_of: false, dependent: nil

  # Deterministic "default company" ordering: oldest accepted membership first.
  # Explicit NULLS FIRST (Postgres defaults to NULLS LAST on ASC) so legacy
  # rows without accepted_at never make the NEWEST company the default; id
  # breaks ties.
  scope :default_order, -> { order(Arel.sql("accepted_at ASC NULLS FIRST"), :id) }

  # Per-company role lives ONLY here (platform-level super_admin is users.super_admin)
  enumerize :role, in: %i[employee admin viewer], default: :employee, predicates: true, scope: true
  enumerize :position, in: POSITIONS, predicates: true

  # Validations
  validates :user_id, uniqueness: { scope: :company_id, message: "already has a membership in this company" }
  validates :preferred_agent_language, inclusion: { in: AGENT_LANGUAGES }, allow_nil: true
  validate :selected_agents_valid
  validate :default_agent_credential_matches_scope
  validate :cannot_remove_last_admin, on: :update
  validate :owned_projects_have_an_heir, on: :update

  # Ransack (members search: by the member's name/email through :user)
  def self.ransackable_attributes(_auth_object = nil)
    %w[role state created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end

  # Invitation link token. The token embeds the membership state AND the
  # invitation timestamp, so any state transition (accept/revoke/suspend) OR a
  # re-invite/re-send (which touches invited_at) invalidates all outstanding
  # tokens — a revoked-then-reinvited membership must not revalidate old links.
  INVITATION_VALID_FOR = 7.days

  generates_token_for :invitation, expires_in: INVITATION_VALID_FOR do
    [ state, invited_at&.to_i ]
  end

  # A revoked member keeps no live company streams: kill their cable
  # connections so open sockets re-authenticate (and lose company channels).
  after_update_commit :disconnect_user_cables, if: -> { saved_change_to_state? && state == "revoked" }

  # In-transaction (not _commit): the transfer and the revocation must land
  # together, or a crash between them leaves projects owned by a non-member.
  after_update :reassign_owned_projects, if: -> { saved_change_to_state? && state == "revoked" }

  # A fresh invited_at (resend / re-invite) starts a new 7-day window, so the
  # one-shot reminder must be allowed to fire again for it.
  before_save :clear_reminded_at, if: :invited_at_changed?

  # Notifications, all _commit so nothing is mailed for a rolled-back change.
  after_update_commit :notify_invitation_accepted, if: -> { saved_change_to_state? && state == "active" && state_before_last_save == "invited" }
  after_update_commit :notify_access_revoked, if: -> { saved_change_to_state? && state == "revoked" }
  after_update_commit :notify_role_changed, if: :saved_change_to_role?

  # ── Onboarding (per company) ────────────────────────────────────────────────

  def onboarding_completed?
    onboarding_state == "completed"
  end

  # Deliberately a DIRECT query rather than the has_many above: these run on
  # memberships taken from User#active_memberships, and reading an association
  # off an already-loaded collection is exactly what Bullet's "USE eager
  # loading" gate rejects — while eager-loading it unconditionally trips the
  # opposite "AVOID eager loading" gate on every request that needs no
  # credentials. See User#active_memberships_with_company for the same tension.
  # Newest first, id breaking ties: without an ORDER BY Postgres returns these
  # in whatever order it likes, and #configured_agents drives which agent the
  # run/session forms preselect when the member has no default credential.
  def credentials_scope
    AgentCredential.where(user_id: user_id, company_id: company_id)
                   .order(created_at: :desc, id: :desc)
  end

  # Loaded once per instance: the current-user props serialise the credentials,
  # list the configured agent types and evaluate needs_agent_setup? on every
  # request, which was three queries for one set of rows.
  def credentials
    @credentials ||= credentials_scope.to_a
  end

  # Agent types this member has authenticated FOR THIS COMPANY.
  def configured_agents
    credentials.map(&:agent_type)
  end

  # Deliberately LIVE, unlike #credentials: this gates the onboarding `complete`
  # transition (can_complete_onboarding?), and a credential created earlier in
  # the same request must not be answered from a stale list.
  def has_configured_agents?
    credentials_scope.exists?
  end

  def default_agent_runtime
    return nil if default_agent_credential_id.blank?

    AgentCredential.find_by(id: default_agent_credential_id)&.agent_type
  end

  # A viewer is read-only, so they never run an agent and onboarding must not
  # demand one. Per-company now: viewer in one company, employee in another.
  def onboarding_requires_agent?
    !viewer?
  end

  def can_complete_onboarding?
    position.present? &&
      preferred_agent_language.present? &&
      (viewer? || has_configured_agents?)
  end

  # Finished onboarding here, but now needs an agent this company has none for —
  # e.g. promoted from viewer to employee. Drives the sidebar nudge and the
  # re-open below.
  def needs_agent_setup?
    # Reads the memoized list: this runs during serialisation, where the
    # credentials have already been loaded.
    onboarding_completed? && onboarding_requires_agent? && credentials.none?
  end

  # Called after a role change or an accepted invitation: send the member back
  # through the agent steps rather than leaving them at empty agent pickers.
  # Returns true when onboarding was re-opened, so callers can redirect.
  def reopen_onboarding_if_setup_needed!
    return false unless needs_agent_setup?

    aasm(:onboarding_state).fire(:reopen)
    save!
    true
  end

  def agent_models_by_type
    credentials.each_with_object({}) do |cred, hash|
      models = fetch_or_cache_agent_models(cred)

      hash[cred.agent_type] = models.map do |m|
        { model_id: m[:model_id] || m["model_id"], display_name: m[:display_name] || m["display_name"], description: m[:description] || m["description"] }
      end
    end
  end

  def agent_models_for_props
    agent_models_by_type.map do |agent_type, models|
      { agent_type: agent_type, models: models }
    end
  end

  private

  # Fetch the model list for a credential, caching per-credential (not globally —
  # the old key collided across users, so one user's fallback poisoned everyone).
  # API-sourced lists are cached for a day; fallback lists only briefly, so a
  # transient API failure or an expired token doesn't pin a stale list for 24h.
  # The cache is also busted whenever the credential's auth data changes
  # (re-auth / refreshed token) — see AgentCredential#invalidate_models_cache.
  def fetch_or_cache_agent_models(cred)
    cache_key = cred.models_cache_key
    cached = Rails.cache.read(cache_key)
    return cached if cached

    adapter = AgentCredentialsService.for(cred.agent_type).adapter
    result = adapter.fetch_available_models_with_source(cred.config_data, credential: cred)
    models = result[:models] || []

    if models.any?
      ttl = result[:source] == :api ? 1.day : 1.hour
      Rails.cache.write(cache_key, models, expires_in: ttl)
    end

    models
  end

  def set_onboarding_completed_at
    self.onboarding_completed_at = Time.current
  end

  def selected_agents_valid
    return if selected_agents.blank?

    invalid_agents = selected_agents - AVAILABLE_AGENTS
    return if invalid_agents.empty?

    errors.add(:selected_agents, "contains invalid agents: #{invalid_agents.join(', ')}")
  end

  # The default must be one of THIS membership's credentials — pointing at
  # another company's credential would run that company's billed token here.
  def default_agent_credential_matches_scope
    return if default_agent_credential_id.blank?
    return if credentials_scope.exists?(id: default_agent_credential_id)

    errors.add(:default_agent_credential_id, "must be a credential of this member in this company")
  end

  def becoming_revoked?
    state == "revoked" && attribute_was(:state) != "revoked"
  end

  # The company's oldest active admin, excluding this member — where projects go
  # when their owner is revoked.
  def heir_membership
    return @heir_membership if defined?(@heir_membership)

    @heir_membership = company.company_memberships
                              .active
                              .where(role: "admin")
                              .where.not(user_id: user_id)
                              .default_order
                              .first
  end

  # Project#owner_belongs_to_company requires the owner to hold an ACTIVE
  # membership, so a revoked owner does not merely look untidy — it makes every
  # project they own fail validation on any later save. Refuse the revocation
  # when there is nowhere to move them.
  def owned_projects_have_an_heir
    return unless becoming_revoked?
    return unless company.projects.exists?(owner_id: user_id)
    return if heir_membership

    errors.add(:base,
               "Cannot remove a member who owns projects while the company has no other admin " \
               "to transfer them to")
  end

  # Guarded by owned_projects_have_an_heir above, so heir_membership is present
  # whenever there is anything to move.
  def reassign_owned_projects
    company.projects.where(owner_id: user_id).find_each do |project|
      project.update!(owner_id: heir_membership.user_id)
    end
  end

  def clear_reminded_at
    self.reminded_at = nil
  end

  # Only when someone actually invited them: a domain auto-join has no inviter,
  # and self-accepted invites would mail the acceptor their own news.
  def notify_invitation_accepted
    return if invited_by_id.blank? || invited_by_id == user_id

    MembershipMailer.invitation_accepted(self).deliver_later
  end

  # A revocation that is part of deleting the whole account is not worth mailing
  # about — the account is gone.
  def notify_access_revoked
    return if user.deleted?

    MembershipMailer.access_revoked(self).deliver_later
  end

  # Skipped while the membership is still `invited`: the role is part of the
  # invitation itself, so a change before acceptance is not news yet. Also
  # skipped on the create-then-set path where there is no previous role.
  def notify_role_changed
    previous_role = role_before_last_save
    return if previous_role.blank? || invited? || revoked?

    MembershipMailer.role_changed(self, previous_role).deliver_later
  end

  def disconnect_user_cables
    ActionCable.server.remote_connections.where(current_user: user).disconnect
  rescue StandardError => e
    Rails.logger.warn("[CompanyMembership] Failed to disconnect cables for user #{user_id}: #{e.message}")
  end

  # Guard: the company's sole active admin membership cannot be demoted or
  # moved out of the active state (revoked/suspended).
  def cannot_remove_last_admin
    was_active_admin = attribute_was(:role) == "admin" && attribute_was(:state) == "active"
    return unless was_active_admin

    still_active_admin = role.to_s == "admin" && state == "active"
    return if still_active_admin

    other_active_admins = company.company_memberships
                                 .where(role: "admin", state: "active")
                                 .where.not(id: id)
    return if other_active_admins.exists?

    errors.add(:base, "Cannot demote or remove the last admin")
  end

  def set_accepted_at
    self.accepted_at = Time.current
  end
end
