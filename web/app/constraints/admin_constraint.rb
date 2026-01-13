# frozen_string_literal: true

class AdminConstraint
  include AuthConcern

  attr_reader :session

  def initialize(request)
    @session = request.session
  end

  def matches?(request)
    true_user.present? && true_user.super_admin?
  end
end
