# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Workflows
        class StepsPolicy < Web::Company::ApplicationPolicy
          def index? = project_accessible?
          def show? = project_accessible?
          def create? = project_writable?
          def update? = project_writable?
          def destroy? = project_writable?
          def reorder? = project_writable?
        end
      end
    end
  end
end
