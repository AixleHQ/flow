# frozen_string_literal: true

class Web::Company::MembersController < Web::Company::ApplicationController
  def index
    memberships = current_company.company_memberships
                                 .where.not(state: "revoked")
                                 .includes(:user, :invited_by)
                                 .ransack(params[:q])
                                 .result
                                 .order(created_at: :desc)

    render inertia: "Company/Members/Index", props: {
      users: memberships.map { |m| MemberResource.new(m).to_h }
    }
  end

  # Invite = find-or-create the global User identity (new users are created
  # passwordless — they set credentials via the invitation signup flow), then
  # create a membership in the `invited` state and email a signed accept link.
  def create
    user = find_or_build_user

    # Invariant: super admins have no memberships — never invite one.
    if user.persisted? && user.super_admin?
      return redirect_to company_members_path,
                         inertia: { errors: { email: "#{user.email} is a platform administrator and cannot be invited" } }
    end

    membership = current_company.company_memberships.find_by(user_id: user.id) if user.persisted?

    if membership.present?
      handle_existing_membership(user, membership)
    else
      invite_new_membership(user)
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent invite of the same email (user or membership unique index).
    redirect_to company_members_path,
                inertia: { errors: { email: "#{create_params[:email]} has already been invited" } }
  end

  # Re-send the invitation email. Touching invited_at rotates the token
  # payload, so the previously mailed link stops working.
  def resend
    membership = member_membership

    if membership.invited?
      membership.update!(invited_at: Time.current)
      MembershipMailer.invitation(membership).deliver_later
      redirect_to company_members_path, notice: "Invitation re-sent to #{membership.user.email}"
    else
      redirect_to company_members_path, alert: "Only pending invitations can be re-sent"
    end
  end

  def update
    membership = member_membership
    assign_role(membership)

    unless fire_state_event(membership)
      # Two-admin race (or a stale UI): the requested transition is no longer
      # valid for the member's current state — report instead of 500ing.
      return redirect_to company_members_path,
                         inertia: { errors: { base: "This action is not available for the member's current state" } }
    end

    if membership.save
      redirect_to company_members_path, notice: "Member updated"
    else
      redirect_to company_members_path, inertia: { errors: membership.errors }
    end
  end

  # Removing a member revokes their membership in THIS company only — the
  # global User identity (and their other memberships) stays intact.
  def destroy
    membership = member_membership
    membership.aasm(:state).fire(:revoke) if membership.may_revoke?

    if membership.revoked? && membership.save
      redirect_to company_members_path, notice: "Member removed"
    else
      redirect_to company_members_path, inertia: { errors: membership.errors }
    end
  end

  private

  ALLOWED_ROLES = CompanyMembership.role.values.freeze
  # Front-end still sends the legacy user-level events; map them onto the
  # membership lifecycle. (The FE never sends "archive" — removal goes through
  # DELETE — so only these two are accepted.)
  ALLOWED_STATE_EVENTS = %w[activate suspend].freeze

  # Revoked rows are invisible to member management (they are re-invitable via
  # #create only) — matching them here would let update/destroy act on ghosts.
  def member_membership
    current_company.company_memberships.where.not(state: "revoked").find_by!(user_id: params[:id])
  end

  def create_params
    params.require(:user).permit(:email, :name)
  end

  def find_or_build_user
    email = create_params[:email].to_s.strip.downcase
    user = User.find_or_initialize_by(email: email)
    user.name = create_params[:name] if user.name.blank? && create_params[:name].present?
    user
  end

  # Existing membership in this company: pending invite → resend; revoked →
  # re-invite (reuse the row — user+company is unique); anything else → error.
  def handle_existing_membership(user, membership)
    if membership.invited?
      membership.update!(invited_at: Time.current)
      MembershipMailer.invitation(membership).deliver_later
      redirect_to company_members_path, notice: "Invitation re-sent to #{user.email}"
    elsif membership.revoked?
      membership.assign_attributes(
        role: allowed_role || "employee",
        invited_by: current_user, invited_at: Time.current, accepted_at: nil
      )
      membership.aasm(:state).fire(:reinvite)
      save_and_send_invitation(user, membership)
    else
      redirect_to company_members_path,
                  inertia: { errors: { email: "#{user.email} is already a member of this company" } }
    end
  end

  def invite_new_membership(user)
    membership = user.company_memberships.build(
      company: current_company,
      role: allowed_role || "employee",
      invited_by: current_user,
      invited_at: Time.current
    )

    if user.save
      MembershipMailer.invitation(membership).deliver_later
      redirect_to company_members_path, notice: "Invitation sent to #{user.email}"
    else
      redirect_to company_members_path, inertia: { errors: user.errors.presence || membership.errors }
    end
  end

  def save_and_send_invitation(user, membership)
    if membership.save
      MembershipMailer.invitation(membership).deliver_later
      redirect_to company_members_path, notice: "Invitation sent to #{user.email}"
    else
      redirect_to company_members_path, inertia: { errors: membership.errors }
    end
  end

  def allowed_role
    role = params.dig(:user, :role)
    role if role.present? && ALLOWED_ROLES.include?(role)
  end

  def assign_role(membership)
    role = allowed_role
    membership.role = role if role.present?
  end

  # Fires the mapped membership event; returns false when the transition is
  # not currently valid (so the caller can surface an error instead of AASM
  # raising InvalidTransition).
  def fire_state_event(membership)
    event = params.dig(:user, :state_event)
    return true if event.blank? || ALLOWED_STATE_EVENTS.exclude?(event)

    membership_event =
      case event
      when "activate" then membership.invited? ? :accept : :reactivate
      when "suspend"  then :suspend
      end

    return false unless membership.aasm(:state).may_fire_event?(membership_event)

    membership.aasm(:state).fire(membership_event)
    true
  end
end
