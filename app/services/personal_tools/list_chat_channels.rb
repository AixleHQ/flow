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
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::IntegrationsPolicy, project: project)

      rows = Chat::ChannelAccess.channels(project, provider: params[:provider].presence).limit(200)
      success(project_id: project.id, channels: rows.map { |row| Chat::ChannelAccess.describe(row) })
    end
  end
end
