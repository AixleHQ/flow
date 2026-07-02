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
  generates_token_for :invitation, expires_in: 7.days do
    [ state, invited_at&.to_i ]
  end

  # A revoked member keeps no live company streams: kill their cable
  # connections so open sockets re-authenticate (and lose company channels).
  after_update_commit :disconnect_user_cables, if: -> { saved_change_to_state? && state == "revoked" }

  private

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
