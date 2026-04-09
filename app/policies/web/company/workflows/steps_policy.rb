# frozen_string_literal: true

module Web
  module Company
    module Workflows
      class StepsPolicy < Web::Company::ApplicationPolicy
        def index? = current_user.admin?
        def show? = current_user.admin?
        def create? = current_user.admin?
        def update? = current_user.admin?
        def destroy? = current_user.admin?
        def reorder? = current_user.admin?
      end
    end
  end
end
