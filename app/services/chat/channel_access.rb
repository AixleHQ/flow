# frozen_string_literal: true

module Chat
  # Which chat channels a project's company may use: the ones connected to it
  # (docs/design/shared-chat-workspaces.md §11.1). Agent tools reach these and
  # the thread their run came from, nothing else.
  module ChannelAccess
    module_function

    # The company's connected channels, through its active installs.
    def channels(project, provider: nil)
      rows = ChatConversation.connected_to_company(project.company_id)
                             .in_workspace_of(Integration.active.visible_for_project(project).select(:id))
                             .order(:team_name, :name, :id)
      provider ? rows.where(provider: provider.to_s) : rows
    end

    # A connected channel named by its registry id, its messenger id, or its
    # name ("#deploys", "deploys"; Teams also "Team/Channel").
    def find(project, provider, value)
      value = value.to_s.strip
      return nil if value.blank?

      scope = channels(project, provider: provider)
      row = scope.find_by(id: value) if value.match?(/\A\d+\z/)
      row || scope.find_by(external_id: value) || by_name(scope, value)
    end

    def by_name(scope, value)
      team, channel = value.include?("/") ? value.split("/", 2).map(&:strip) : [ nil, value ]
      rows = scope.where("lower(chat_conversations.name) = ?", channel.delete_prefix("#").downcase)
      rows = rows.where("lower(chat_conversations.team_name) = ?", team.downcase) if team
      rows.one? ? rows.first : nil
    end

    # The project's company's own install of the workspace a channel lives in.
    def install_for(project, conversation)
      installs = Integration.active.visible_for_project(project).where(provider: conversation.provider)
      installs = if conversation.chat_workspace_id
        installs.where(chat_workspace_id: conversation.chat_workspace_id)
      else
        installs.where(id: conversation.integration_id)
      end
      installs.order(:id).first
    end

    def not_connected(project, provider, value)
      label = Chat.provider(provider)&.label || provider.to_s
      known = channels(project, provider: provider).limit(20).map(&:label)
      "#{value.to_s.strip.inspect} is not a #{label} channel connected to #{project.company.name}. " \
        "Connected: #{known.join(', ').presence || 'none'}. " \
        "Connect one in Aixle: Integrations → #{label} → Connect a channel."
    end

    def describe(row)
      { id: row.id, name: row.name, label: row.label, kind: row.kind.to_s, team_name: row.team_name,
        provider: row.provider }
    end
  end
end
