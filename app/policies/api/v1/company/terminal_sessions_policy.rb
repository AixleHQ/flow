# frozen_string_literal: true

module Api
  module V1
    module Company
      class TerminalSessionsPolicy < ApplicationPolicy
        def index?
          true
        end

        def show?
          true
        end
      end
    end
  end
end
