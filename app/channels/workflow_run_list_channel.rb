# frozen_string_literal: true

class WorkflowRunListChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    project_id = params[:project_id].presence&.to_i
    return reject unless project_id

    member_company_ids = current_user.company_memberships.active.select(:company_id)
    project = Project.where(company_id: member_company_ids).find_by(id: project_id)
    return reject unless project

    stream_from "workflow_run_list:project:#{project_id}"
  end
end
