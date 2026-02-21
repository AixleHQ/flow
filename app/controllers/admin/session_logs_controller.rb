# frozen_string_literal: true

module Admin
  class SessionLogsController < Admin::ApplicationController
    def show
      log = SessionLog.find(params[:id])
      if params[:download].present?
        send_log_file(log)
      else
        super
      end
    end

    def default_sorting_attribute
      :id
    end

    def default_sorting_direction
      :desc
    end

    private

    def send_log_file(log)
      url = log.file_url
      if url.present?
        redirect_to url, allow_other_host: true
      else
        flash[:error] = "File not available"
        redirect_to [ :admin, log ]
      end
    end
  end
end
