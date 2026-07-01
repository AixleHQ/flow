# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SessionsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = project_accessible?
        def new? = project_writable?
      end
    end
  end
end
