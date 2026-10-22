# frozen_string_literal: true

module PersonalTools
  class CreateChatConnectCode < Base
    tool do
      display_name "Create Chat Connect Code"
      description "Ask for a one-time code that connects one named Slack or Microsoft Teams channel to the project's " \
                  "company; posted in any other channel it connects nothing. " \
                  "A person in that channel invites the bot (the `invite` field), then mentions the bot by its name " \
                  "(the `mention` field, picked from the list as they type) followed by the `command` field; the bot " \
                  "confirms in the channel. The code works once, for 10 minutes. With trigger_id, the chat trigger is " \
                  "pointed at the channel once it is connected; switching the trigger on stays a separate step. " \
                  "get_chat_connect_code reports whether it was used."
      audience :user
      tags :integrations, :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :provider, type: :string, enum: Chat::PROVIDERS.keys, required: true, description: "The messenger."
      param :channel, type: :string, required: true,
                      description: "The channel to connect, as people see it: Slack \"#deploys\" or \"deploys\"; Teams " \
                                   "\"Team / Channel\", or a group chat's name."
      param :trigger_id, type: :integer, description: "A chat trigger of this project to point at the channel."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      trigger = TriggerBinding.where(project: project).find_by(id: params[:trigger_id]) if params[:trigger_id].present?
      return error("Trigger #{params[:trigger_id]} not found in project #{project.id}") if params[:trigger_id].present? && trigger.nil?

      _record, payload = Chat::ConnectCodes.issue!(project: project, provider: params[:provider], channel: params[:channel],
                                                   user: user, trigger_binding: trigger)
      success(payload)
    rescue Chat::ConnectCodes::Refused => e
      error(e.message)
    end
  end
end
