# frozen_string_literal: true

module AuthConcern
  extend ActiveSupport::Concern

  IMPERSONATION_KEY = "true_user_id"

  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session[:user_id] = nil
    @current_user = nil
  end

  def signed_in?
    session[:user_id].present? && current_user.present?
  end

  def authenticate_user!
    head(:unauthorized) unless signed_in?
  end

  def authenticate_admin!
    redirect_to("/login") unless signed_in? && true_user.super_admin?
  end

  def current_user
    @current_user ||= User.with_state(:active).find_by(id: session[:user_id])
  end

  def true_user
    @true_user ||= User.find_by(id: session[IMPERSONATION_KEY] || session[:user_id])
  end

  def impersonate_user(user)
    session[IMPERSONATION_KEY] = true_user.id
    @current_user = nil
    sign_in(user)
  end

  def stop_impersonating_user
    true_user_id = session.delete(IMPERSONATION_KEY)
    true_user = User.find(true_user_id)
    @current_user = nil

    sign_in(true_user)
  end

  def impersonated?
    session[IMPERSONATION_KEY].present?
  end
end

