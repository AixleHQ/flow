# frozen_string_literal: true

module Chat
  # Which Teams conversation a chat tool call means: the one the run was started
  # from, or a channel connected to the project's company (Chat::ChannelAccess),
  # named by its registry id, its Teams id, or "Team/Channel" — never a
  # conversation an id from elsewhere points at.
  module TargetResolver
    module_function

    # [conversation, error message]
    def teams(project, value, origin)
      installed = ChatConversation.where(provider: "teams",
                                         integration: Integration.active.visible_for_project(project).where(provider: :teams))
      return from_origin(installed, origin) if value.blank?

      value = value.to_s.strip
      origin_row = from_origin(installed, origin).first if origin.to_h["provider"] == "teams"
      return [ origin_row, nil ] if origin_row && [ origin_row.id.to_s, origin_row.external_id ].include?(value)

      scope = installed.connected_to_company(project.company_id)
      row = scope.find_by(id: value) if value.match?(/\A\d+\z/)
      row ||= scope.find_by(external_id: value)
      return [ row, nil ] if row

      by_name(scope, value)
    end

    def from_origin(scope, origin)
      origin = origin.to_h
      unless origin["provider"] == "teams"
        return [ nil, "No conversation given, and this run was not started from Teams — pass `conversation`." ]
      end

      row = scope.find_by(integration_id: origin["integration_id"], external_id: origin.dig("conversation", "id"))
      row ? [ row, nil ] : [ nil, "The Teams conversation this run came from is no longer connected." ]
    end

    def by_name(scope, value)
      team, channel = value.include?("/") ? value.split("/", 2).map(&:strip) : [ nil, value ]
      rows = scope.where("lower(name) = ?", channel.delete_prefix("#").downcase)
      rows = rows.where("lower(team_name) = ?", team.downcase) if team
      rows = rows.to_a
      return [ rows.first, nil ] if rows.one?

      known = (rows.presence || scope.where.not(name: nil).limit(20).to_a).map { |row| [ row.team_name, row.name ].compact.join("/") }
      what = if rows.many?
        "#{value.inspect} matches more than one connected conversation"
      else
        "No Teams conversation connected to this company is named #{value.inspect}"
      end
      [ nil, "#{what}. Connected: #{known.uniq.join(', ').presence || 'none'}. " \
             "Connect one in Aixle: Integrations → Microsoft Teams → Connect a channel." ]
    end
  end
end
