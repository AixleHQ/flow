# frozen_string_literal: true

module Chat
  # What /status lists (docs/design/teams-integration.md §20): the last runs
  # started from one conversation, by a trigger or by someone, and only from
  # projects the asker may open in Aixle — a quiet trigger's runs never showed
  # themselves in the conversation.
  module RecentRuns
    LIMIT = 10
    WINDOW = 30.days

    module_function

    def for(user, integration, provider:, conversation_id:)
      project_ids = RunCatalog.active_projects(integration).select { |project| project.accessible_by?(user) }.map(&:id)
      WorkflowRun.where(project_id: project_ids, created_at: WINDOW.ago..)
                 .where("shared_context -> 'chat' ->> 'provider' = ?", provider)
                 .where("shared_context -> 'chat' -> 'conversation' ->> 'id' = ?", conversation_id)
                 .includes(:workflow).order(created_at: :desc).limit(LIMIT)
    end
  end
end
