# frozen_string_literal: true

module Api
  module V1
    module Projects
      class ChatChannelsPolicy < Api::V1::ApplicationPolicy
        def index? = project_accessible?
        def destroy? = project_writable?
      end
    end
  end
end
