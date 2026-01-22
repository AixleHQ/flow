# frozen_string_literal: true

module Admin
  class ApplicationController < Administrate::ApplicationController
    include AuthConcern

    helper_method :current_user, :true_user, :impersonated?

    before_action :authenticate_admin!

    def records_per_page
      params[:per_page] || 20
    end
  end
end
