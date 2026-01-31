# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Note: pundit_user returns current_user directly (not a context object)
  # So we access user via the context reader which is set in initialize

  def index?
    current_user.admin?
  end

  def create?
    current_user.admin?
  end

  def update?
    current_user.admin? && same_company?
  end

  def destroy?
    current_user.admin? && same_company? && not_self?
  end

  private

  def current_user
    # context can be either a User or a context object with .user method
    context.respond_to?(:user) ? context.user : context
  end

  def same_company?
    record.company_id == current_user.company_id
  end

  def not_self?
    record.id != current_user.id
  end
end
