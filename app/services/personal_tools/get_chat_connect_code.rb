# frozen_string_literal: true

module PersonalTools
  class GetChatConnectCode < Base
    tool do
      display_name "Get Chat Connect Code"
      description "Report a connect code from create_chat_connect_code: pending, redeemed (with the channel it " \
                  "connected) or expired, and why a failed attempt to use it was refused."
      audience :user
      tags :integrations, :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :code_id, type: :integer, description: "The `id` create_chat_connect_code returned.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::IntegrationsPolicy, project: project)
      record = ChatConnectCode.where(project: project).find_by(id: params[:code_id])
      return error("Connect code #{params[:code_id]} not found in project #{project.id}") if record.nil?

      success(Chat::ConnectCodes.describe(record, project: project))
    end
  end
end
