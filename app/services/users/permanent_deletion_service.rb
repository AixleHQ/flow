# frozen_string_literal: true

module Users
  # Irreversibly removes a non–super-admin user: the `users` row and all personal
  # data are destroyed, owned projects are transferred to a company heir admin,
  # and history/authorship rows survive with their actor nullified (FKs are
  # ON DELETE :nullify — see the EnablePermanentUserDeletion migration).
  #
  # Personal data (memberships, credentials, MCP token columns, favourites,
  # collaborators, terminal sessions, board view presets) is removed by the
  # `dependent: :destroy` associations on User. Everything runs in one
  # transaction, so a failure anywhere leaves the user fully intact.
  #
  # Contrast with User#soft_delete!, which only sets `deleted_at` and is still
  # the default admin "Delete".
  class PermanentDeletionService
    class Error < StandardError; end
    class SuperAdminProtected < Error; end
    class OwnershipTransferError < Error; end

    def self.call(user:, actor:) = new(user:, actor:).call

    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call
      raise SuperAdminProtected, "Super admin users cannot be permanently deleted" if @user.super_admin?

      ensure_owned_projects_transferable!

      ActiveRecord::Base.transaction do
        audit!
        transfer_owned_projects!
        @user.destroy!
      end
    end

    private

    # Refuse before touching anything if any company where the user owns projects
    # has no other active admin to inherit them. Mirrors CompanyMembership's
    # #owned_projects_have_an_heir guard: a project must never be left with an
    # owner who is not an active member of its company.
    def ensure_owned_projects_transferable!
      companies_with_owned_projects.each do |company|
        next if heir_membership_for(company)

        raise OwnershipTransferError,
              "Cannot permanently delete #{@user.email}: they own projects in " \
              "\"#{company.name}\", which has no other admin to transfer ownership to. " \
              "Appoint another admin or reassign the projects first."
      end
    end

    # Reassign each owned project to ITS OWN company's heir admin. Grouping by
    # company matters — a user can own projects across several companies, and
    # each project must go to an active admin of the company that owns it.
    def transfer_owned_projects!
      companies_with_owned_projects.each do |company|
        heir = heir_membership_for(company)
        company.projects.where(owner_id: @user.id).find_each do |project|
          project.update!(owner_id: heir.user_id)
        end
      end
    end

    # Durable record of who/when/which email+id — but NOT the full profile, so no
    # recoverable copy survives (GDPR). The auditable_id will dangle after the
    # destroy; identity lives in audited_changes and the comment.
    def audit!
      Audited::Audit.create!(
        auditable: @user,
        action: "permanent_delete",
        user: @actor,
        audited_changes: { "id" => @user.id, "email" => @user.email },
        comment: "#{@actor&.email} permanently deleted #{@user.email} (id=#{@user.id})"
      )
    end

    def companies_with_owned_projects
      @companies_with_owned_projects ||=
        Company.where(id: Project.where(owner_id: @user.id).select(:company_id)).to_a
    end

    # The company's oldest active admin other than this user — the same
    # heir-selection rule CompanyMembership uses when a project owner is revoked.
    def heir_membership_for(company)
      (@heirs ||= {})[company.id] ||=
        company.company_memberships
               .active
               .where(role: "admin")
               .where.not(user_id: @user.id)
               .default_order
               .first
    end
  end
end
