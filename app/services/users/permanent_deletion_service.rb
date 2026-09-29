# frozen_string_literal: true

module Users
  # Irreversibly removes a non–super-admin user: the `users` row and all personal
  # data are destroyed, owned projects are transferred to a company heir admin,
  # and history/authorship rows survive with their actor nullified (FKs are
  # ON DELETE :nullify — see the EnablePermanentUserDeletion migration).
  #
  # Personal data (memberships, credentials, OAuth connections, browser
  # sessions, MCP token columns, favourites, collaborators, board view presets)
  # is removed by the `dependent:` associations on User. Terminal sessions are
  # the company's record of work done and spent — its analytics are built on
  # them — so they stay, attributed to "Deleted user". Everything runs in one
  # transaction, so a failure anywhere leaves the user fully intact.
  #
  # Contrast with User#soft_delete!, which only sets `deleted_at` and is still
  # the default admin "Delete".
  class PermanentDeletionService
    class Error < StandardError; end
    class SuperAdminProtected < Error; end
    class OwnershipTransferError < Error; end
    class LastAdminError < Error; end
    class LiveSessionsError < Error; end

    def self.call(user:, actor:) = new(user:, actor:).call

    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call
      raise SuperAdminProtected, "Super admin users cannot be permanently deleted" if @user.super_admin?

      ensure_owned_projects_transferable!
      ensure_not_the_last_admin!
      ensure_no_live_sessions!

      ActiveRecord::Base.transaction do
        audit!
        transfer_owned_projects!
        # transfer_owned_projects! moves ownership with a direct UPDATE, which
        # does not touch @user's already-loaded owned_projects proxy. Without
        # this reset the has_many :owned_projects, dependent: :restrict_with_error
        # guard sees the stale in-memory collection and aborts destroy!.
        @user.owned_projects.reset
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

    # A company must keep an admin; deleting its last one would leave nobody who
    # can manage it (CompanyMembership refuses too — this says why, up front).
    def ensure_not_the_last_admin!
      @user.company_memberships.active.where(role: "admin").includes(:company).find_each do |membership|
        next if CompanyMembership.heir_for(membership.company, excluding_user: @user)

        raise LastAdminError,
              "Cannot permanently delete #{@user.email}: they are the only admin of " \
              "\"#{membership.company.name}\". Appoint another admin first."
      end
    end

    # Sessions stay as history, and history is finished: a running one would be
    # left running with nobody to own it.
    def ensure_no_live_sessions!
      live = TerminalSession.where(user_id: @user.id).where.not(state: TerminalSession::TERMINAL_STATES).count
      return if live.zero?

      raise LiveSessionsError,
            "Cannot permanently delete #{@user.email}: #{live} of their sessions are still running. Stop them first."
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
      Audit.create!(
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

    def heir_membership_for(company)
      (@heirs ||= {})[company.id] ||=
        CompanyMembership.heir_for(company, excluding_user: @user)
    end
  end
end
