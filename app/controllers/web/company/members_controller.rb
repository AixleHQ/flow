# frozen_string_literal: true

class Web::Company::MembersController < Web::Company::ApplicationController
  def index
    users = current_company.users
                           .includes(:invited_by)
                           .ransack(params[:q])
                           .result
                           .order(created_at: :desc)

    render inertia: "Company/Members/Index", props: {
      users: users.map { |u| UserResource.new(u).to_h }
    }
  end

  def create
    user = current_company.users.new(create_params.merge(inviter: current_user))
    user.state = "pending"
    assign_role(user)

    if user.save
      redirect_to company_members_path, notice: "Invitation sent to #{user.email}"
    else
      redirect_to company_members_path, inertia: { errors: user.errors }
    end
  end

  def update
    user = current_company.users.find(params[:id])
    assign_role(user)
    fire_state_event(user)

    if user.save
      redirect_to company_members_path, notice: "Member updated"
    else
      redirect_to company_members_path, inertia: { errors: user.errors }
    end
  end

  def destroy
    user = current_company.users.find(params[:id])
    user.destroy
    redirect_to company_members_path, notice: "Member removed"
  end

  private

  # super_admin cannot be granted by company admins — only seeded or promoted
  # by a super_admin in the admin panel.
  ALLOWED_ROLES = (User.role.values - ["super_admin"]).freeze
  ALLOWED_STATE_EVENTS = %w[activate suspend archive].freeze

  def create_params
    params.require(:user).permit(:email, :name)
  end

  def assign_role(user)
    role = params.dig(:user, :role)
    user.role = role if role.present? && ALLOWED_ROLES.include?(role)
  end

  def fire_state_event(user)
    event = params.dig(:user, :state_event)
    user.aasm(:state).fire(event.to_sym) if event.present? && ALLOWED_STATE_EVENTS.include?(event)
  end
end
