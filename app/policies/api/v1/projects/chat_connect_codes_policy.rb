# frozen_string_literal: true

module Api
  module V1
    module Projects
      # Asking for a code is what managing a project's triggers allows.
      class ChatConnectCodesPolicy < Api::V1::ApplicationPolicy
        def create? = project_writable?
        def show? = project_accessible?
      end
    end
  end
end
