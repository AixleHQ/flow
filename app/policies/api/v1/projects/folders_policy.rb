# frozen_string_literal: true

module Api
  module V1
    module Projects
      class FoldersPolicy < Api::V1::ApplicationPolicy
        def create? = project_writable?
        def relocate? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
