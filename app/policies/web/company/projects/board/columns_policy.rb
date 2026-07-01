# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        class ColumnsPolicy < Web::Company::ApplicationPolicy
          def index? = project_accessible?
          def show? = project_accessible?
          def create? = project_admin?
          def update? = project_admin?
          def destroy? = project_admin?
          def reorder? = project_admin?

          private

          def project_admin?
            project_writable? && project&.admin?(current_user)
          end
        end
      end
    end
  end
end
