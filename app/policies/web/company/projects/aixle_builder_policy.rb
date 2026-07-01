# frozen_string_literal: true

module Web
  module Company
    module Projects
      class AixleBuilderPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def show_session? = project_accessible?
        def start? = project_writable?
        def finish? = project_writable?
      end
    end
  end
end
