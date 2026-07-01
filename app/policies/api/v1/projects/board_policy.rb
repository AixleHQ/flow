# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BoardPolicy < Web::Company::Projects::BoardsPolicy
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
        def create_from_preset? = project_writable?
      end
    end
  end
end
