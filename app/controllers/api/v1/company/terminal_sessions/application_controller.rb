# frozen_string_literal: true

module Api
  module V1
    module Company
      module TerminalSessions
        class ApplicationController < Api::V1::Company::ApplicationController
          def current_session
            @current_session ||= current_user.terminal_sessions.find(params[:terminal_session_id])
          end
        end
      end
    end
  end
end
