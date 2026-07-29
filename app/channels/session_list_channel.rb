# frozen_string_literal: true

class SessionListChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    if (project_id = params[:project_id].presence&.to_i)
      # Project streams are open to members of the project's company.
      member_company_ids = current_user.company_memberships.active.select(:company_id)
      project = Project.where(company_id: member_company_ids).find_by(id: project_id)
      return reject unless project

      stream_from "session_list:project:#{project_id}"
    else
      # Company stream = the session-validated current company (see Connection).
      return reject unless current_company

      stream_from "session_list:company:#{current_company.id}"
    end
  end
end
