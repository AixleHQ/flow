# frozen_string_literal: true

module Api
  module V1
    module Company
      module TerminalSessions
        class ArtifactsPolicy < Company::ApplicationPolicy
          def index?
            true
          end

          def review?
            true
          end

          def download?
            true
          end
        end
      end
    end
  end
end
