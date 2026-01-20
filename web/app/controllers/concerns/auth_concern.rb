# frozen_string_literal: true

module AuthConcern
  extend ActiveSupport::Concern

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

  def current_user
    @current_user ||= User.with_status(:active).find_by(id: session[:user_id])
  end
end
