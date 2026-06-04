# frozen_string_literal: true

class SessionListChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    if (project_id = params[:project_id].presence&.to_i)
      project = current_user.company&.projects&.find_by(id: project_id)
      return reject unless project

      stream_from "session_list:project:#{project_id}"
    else
      company = current_user.company
      return reject unless company

      stream_from "session_list:company:#{company.id}"
    end
  end
end
