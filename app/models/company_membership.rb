# frozen_string_literal: true

class CompanyMembership < ApplicationRecord
  extend Enumerize

  # State machine (invited -> active, suspend/reactivate, revoke)
  include CompanyMembershipStateMachine

  # Associations
  belongs_to :user
  belongs_to :company
  belongs_to :invited_by, class_name: "User", optional: true

  # Deterministic "default company" ordering: oldest accepted membership first.
  # Explicit NULLS FIRST (Postgres defaults to NULLS LAST on ASC) so legacy
  # rows without accepted_at never make the NEWEST company the default; id
  # breaks ties.
  scope :default_order, -> { order(Arel.sql("accepted_at ASC NULLS FIRST"), :id) }

  # Per-company role lives ONLY here (platform-level super_admin is users.super_admin)
  enumerize :role, in: %i[employee admin viewer], default: :employee, predicates: true, scope: true

  # Validations
  validates :user_id, uniqueness: { scope: :company_id, message: "already has a membership in this company" }
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

  private

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

  # Only when someone actually invited them: a domain auto-join has no inviter,
  # and self-accepted invites would mail the acceptor their own news.
  def clear_reminded_at
    self.reminded_at = nil
  end

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
