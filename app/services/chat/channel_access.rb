# frozen_string_literal: true

module Chat
  # Which chat channels a project's company may use: the ones connected to it
  # (docs/design/shared-chat-workspaces.md §11.1). Agent tools reach these and
  # the thread their run came from, nothing else.
  module ChannelAccess
    module_function

    def installs(project, provider: nil)
      Integration.active.visible_for_project(project).where(provider: provider&.to_s || Chat::PROVIDERS.keys)
    end

    # The company's connected channels, through its active installs, or in the
    # workspace of one of them.
    def channels(project, provider: nil, integration: nil)
      rows = ChatConversation.connected_to_company(project.company_id)
                             .in_workspace_of(integration ? integration.id : installs(project).select(:id))
                             .order(:team_name, :name, :id)
      provider ? rows.where(provider: provider.to_s) : rows
    end

    # A connected channel named by its registry id, its messenger id, or its
    # name ("#deploys", "deploys"; "Workspace/#deploys" in Slack; Teams also
    # "Team/Channel").
    def find(project, provider, value)
      value = value.to_s.strip
      return nil if value.blank?

      scope = channels(project, provider: provider)
      row = scope.find_by(id: value) if value.match?(/\A\d+\z/)
      row || scope.find_by(external_id: value) || by_name(scope, value)
    end

    def by_name(scope, value)
      rows = named(scope, value)
      rows.one? ? rows.first : nil
    end

    # A Slack channel is qualified by its workspace, a Teams channel by its team.
    def named(scope, value)
      team, channel = value.include?("/") ? value.split("/", 2).map(&:strip) : [ nil, value ]
      rows = scope.where("lower(chat_conversations.name) = ?", channel.delete_prefix("#").downcase)
      return rows unless team

      rows.left_joins(:chat_workspace)
          .where("lower(coalesce(chat_conversations.team_name, chat_workspaces.name)) = ?", team.downcase)
    end

    # The project's company's own install of the workspace a channel lives in.
    def install_for(project, conversation)
      rows = installs(project, provider: conversation.provider)
      rows = if conversation.chat_workspace_id
        rows.where(chat_workspace_id: conversation.chat_workspace_id)
      else
        rows.where(id: conversation.integration_id)
      end
      rows.order(:id).first
    end

    def not_connected(project, provider, value)
      label = Chat.provider(provider)&.label || provider.to_s
      scope = channels(project, provider: provider)
      rows = scope.preload(:chat_workspace).limit(20).to_a
      several = rows.map(&:workspace_name).uniq.many?
      known = rows.map { |row| several ? qualified_label(row) : row.label }
      what = if named(scope, value.to_s.strip).many?
        "#{value.to_s.strip.inspect} names a #{label} channel in more than one workspace connected to " \
          "#{project.company.name} — name it as Workspace/#channel."
      else
        "#{value.to_s.strip.inspect} is not a #{label} channel connected to #{project.company.name}."
      end
      "#{what} Connected: #{known.join(', ').presence || 'none'}. " \
        "Connect one in Aixle: Integrations → #{label} → Connect a channel."
    end

    def qualified_label(row)
      row.provider == "slack" && row.workspace_name ? "#{row.workspace_name}/#{row.label}" : row.label
    end

    def describe(row)
      { id: row.id, name: row.name, label: row.label, kind: row.kind.to_s, team_name: row.team_name,
        workspace: row.workspace_name, provider: row.provider }
    end
  end
end
