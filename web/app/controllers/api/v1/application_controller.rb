# frozen_string_literal: true

module Api
  module V1
    class ApplicationController < ::ApplicationController
      include Pundit::Authorization
      include AuthorizationConcern
      include PaginationConcern

      self.responder = JsonResponder
      respond_to :json

      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
    end
  end
end
