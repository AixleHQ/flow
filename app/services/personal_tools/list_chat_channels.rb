# frozen_string_literal: true

module PersonalTools
  class ListChatChannels < Base
    tool do
      display_name "List Chat Channels"
      description "List the Slack and Microsoft Teams channels connected to a project's company: the channels its " \
                  "chat triggers can listen to (pass the id as chat_channel_id) and its workflows can post to. " \
                  "A channel not listed is connected with create_chat_connect_code."
      audience :user
      tags :integrations, :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :provider, type: :string, enum: Chat::PROVIDERS.keys, description: "Only this messenger's channels."
      param :integration_id, type: :integer,
                             description: "Only the channels in this Slack or Teams integration's workspace (list_integrations)."
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::IntegrationsPolicy, project: project)
      if params[:integration_id].present?
        integration = Chat::ChannelAccess.installs(project).find_by(id: params[:integration_id])
        return error("No active Slack or Teams integration #{params[:integration_id]} in project #{project.id}") if integration.nil?
      end

      rows = Chat::ChannelAccess.channels(project, provider: params[:provider].presence, integration: integration)
                                 .preload(:chat_workspace).limit(200)
      success(project_id: project.id, channels: rows.map { |row| Chat::ChannelAccess.describe(row) })
    end
  end
end
