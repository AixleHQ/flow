# frozen_string_literal: true

module AuthorizationConcern
  extend ActiveSupport::Concern

  def dynamic_authorize!
    authorize(policy_method_params)
  end

  def pundit_user
    policy_context
  end

  private

  def policy_method_params
    controller_class = self.class.to_s

    params = controller_class.gsub(/Controller/, "").split("::")
    params.map(&:underscore).map(&:downcase).map(&:to_sym)
  end
end
