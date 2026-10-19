# frozen_string_literal: true

module Admin
  # Invites people into a company as its own admins would from Members
  # (CompanyInvitation), so an operator setting a tenant up need not sign in as
  # its admin to bring the team in. Not an Administrate resource: the company's
  # members and a form.
  class CompanyInvitationsController < Admin::ApplicationController
    before_action :set_company

    def new
      @memberships = @company.company_memberships.where.not(state: "revoked")
                             .joins(:user).where(users: { deleted_at: nil })
                             .includes(:user, :invited_by)
                             .order(created_at: :desc)

      render layout: "administrate/application"
    end

    def create
      results = CompanyInvitation.invite_all(company: @company, addresses: params[:emails], role: params[:role])
      return redirect_to(new_admin_company_invitation_path(@company), alert: "Enter at least one email address.") if results.empty?

      redirect_to new_admin_company_invitation_path(@company), **invitation_flash(results)
    end

    def resend
      membership = @company.company_memberships.where.not(state: "revoked").find(params[:id])
      unless membership.invited?
        return redirect_to(new_admin_company_invitation_path(@company), alert: "Only pending invitations can be re-sent.")
      end

      result = CompanyInvitation.call(company: @company, email: membership.user.email)
      redirect_to new_admin_company_invitation_path(@company), (result.sent? ? :notice : :alert) => "#{result.message}."
    end

    private

    def set_company
      @company = Company.find(params[:company_id])
    end
  end
end
