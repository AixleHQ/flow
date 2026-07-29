# frozen_string_literal: true

# Idempotent data migration: convert users.company_id/role/invited_by_id/invited_at
# into CompanyMembership rows, and users.role == "super_admin" into the
# users.super_admin boolean (super admins get NO membership).
class BackfillCompanyMemberships < ActiveRecord::Migration[8.1]
  MEMBERSHIP_ROLES = %w[employee admin viewer].freeze

  # Legacy account state → membership state. Suspended/archived users must NOT
  # come out with an active membership.
  STATE_MAP = {
    "pending" => "invited",
    "suspended" => "suspended",
    "archived" => "revoked"
  }.freeze

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationMembership < ActiveRecord::Base
    self.table_name = "company_memberships"
  end

  def up
    MigrationUser.reset_column_information

    MigrationUser.where(role: "super_admin").update_all(super_admin: true)

    MigrationUser.where.not(company_id: nil).where(role: MEMBERSHIP_ROLES).find_each do |user|
      next if MigrationMembership.exists?(user_id: user.id, company_id: user.company_id)

      state = STATE_MAP.fetch(user.state, "active")
      MigrationMembership.create!(
        user_id: user.id,
        company_id: user.company_id,
        role: user.role,
        state: state,
        invited_by_id: user.invited_by_id,
        invited_at: user.invited_at,
        # Existing active members "accepted" when their account was created —
        # NULL here would make the NEWEST company the default (NULLS LAST).
        accepted_at: state == "active" ? user.created_at : nil
      )
    end

    # Legacy "pending" gating now lives on the membership (state: invited).
    # Leaving users.state = "pending" would strand them: User.active login
    # scope locks them out even after their membership is activated.
    MigrationUser.where(state: "pending", super_admin: false).update_all(state: "active")
  end

  def down
    # Data-only migration; memberships are dropped with the table on full rollback.
  end
end
