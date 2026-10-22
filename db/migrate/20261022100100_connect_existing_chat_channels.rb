# frozen_string_literal: true

# Connects the channels each company already uses to that company, and points
# every chat trigger at exactly one of them (docs/design/shared-chat-workspaces.md
# §15.2, decisions 12 and 13). Everything is read from the database as it runs:
# this repository is public, so nothing here names a channel, a trigger or a
# company, and only counts are logged.
class ConnectExistingChatChannels < ActiveRecord::Migration[8.1]
  CHAT = "chat.message"
  SLACK_CHANNEL = /\A[CG][A-Z0-9]{8,}\z/
  # An id-shaped token with a digit in it, so words like CHECKLIST are skipped.
  INSTRUCTION_CHANNEL = /\b([CG](?=[A-Z0-9]*\d)[A-Z0-9]{8,12})\b/
  ROUTING_ROOTS = %w[channel conversation workspace team integration_id subject service_url].freeze
  RECENT = 90.days

  class MigrationIntegration < ActiveRecord::Base
    self.table_name = "integrations"
  end

  class MigrationConversation < ActiveRecord::Base
    self.table_name = "chat_conversations"
  end

  class MigrationConnection < ActiveRecord::Base
    self.table_name = "chat_channel_connections"
  end

  class MigrationBinding < ActiveRecord::Base
    self.table_name = "trigger_bindings"
  end

  class MigrationProject < ActiveRecord::Base
    self.table_name = "projects"
  end

  class MigrationWorkflow < ActiveRecord::Base
    self.table_name = "workflows"
  end

  def up
    @counts = Hash.new(0)
    connect_teams_conversations
    connect_slack_channels
    bind_chat_triggers
    say "chat channels: #{@counts.sort.map { |key, value| "#{key}=#{value}" }.join(', ')}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Every Teams channel and group chat the bot already serves stays usable.
  def connect_teams_conversations
    companies = MigrationIntegration.where(provider: "teams").pluck(:id, :company_id).to_h
    MigrationConversation.where(provider: "teams").where.not(kind: "direct").find_each do |conversation|
      company_id = companies[conversation.integration_id]
      connect(conversation, company_id) if company_id
    end
  end

  def connect_slack_channels
    slack_channel_pairs.each do |integration_id, channel|
      integration = slack_integrations_by_id[integration_id]
      next unless integration

      conversation = MigrationConversation.find_or_create_by!(integration_id: integration_id, external_id: channel) do |row|
        row.provider = "slack"
        row.kind = "channel"
      end
      connect(conversation, integration.company_id)
    end
  end

  # [integration_id, channel id] pairs from every place a channel is already used.
  def slack_channel_pairs
    pairs = Set.new
    trigger_channels.each { |pair| pairs << pair }
    event_channels.each { |pair| pairs << pair }
    run_channels.each { |pair| pairs << pair }
    instruction_channels.each { |pair| pairs << pair }
    pairs.select { |integration_id, channel| integration_id && channel.to_s.match?(SLACK_CHANNEL) }
  end

  def trigger_channels
    MigrationBinding.where(event_type: CHAT).filter_map do |binding|
      filter = binding.filter_predicate.to_h
      next unless filter["provider"] == "slack" && filter["channel"].is_a?(String)

      [ default_slack_integration_id(company_of_project(binding.project_id)), filter["channel"] ]
    end
  end

  def event_channels
    recent = connection.select_all(<<~SQL.squish).to_a
      SELECT DISTINCT data->>'integration_id' AS integration_id, data->>'channel' AS channel
      FROM trigger_events
      WHERE event_type = '#{CHAT}' AND data->>'provider' = 'slack'
        AND (created_at > NOW() - INTERVAL '#{RECENT.in_days.to_i} days'
             OR id IN (SELECT trigger_event_id FROM trigger_dispatches WHERE trigger_binding_id IS NOT NULL))
    SQL
    recent.map { |row| [ row["integration_id"]&.to_i, row["channel"] ] }
  end

  def run_channels
    rows = connection.select_all(<<~SQL.squish).to_a
      SELECT DISTINCT shared_context->'chat'->>'integration_id' AS integration_id,
                      shared_context->'chat'->'conversation'->>'id' AS channel
      FROM workflow_runs
      WHERE shared_context->'chat'->>'provider' = 'slack'
        AND created_at > NOW() - INTERVAL '#{RECENT.in_days.to_i} days'
    SQL
    rows.map { |row| [ row["integration_id"]&.to_i, row["channel"] ] }
  end

  # Workflows that post to a channel no trigger listens on name it in a step.
  def instruction_channels
    rows = connection.select_all(<<~SQL.squish).to_a
      SELECT workflows.scope_type, workflows.scope_id, texts.body
      FROM workflows
      JOIN (
        SELECT steps.workflow_id, steps.instructions AS body FROM steps WHERE steps.deleted_at IS NULL
        UNION ALL
        SELECT steps.workflow_id, sub_steps.instructions FROM sub_steps
        JOIN steps ON steps.id = sub_steps.step_id
        WHERE steps.deleted_at IS NULL AND sub_steps.deleted_at IS NULL
      ) texts ON texts.workflow_id = workflows.id
      WHERE workflows.deleted_at IS NULL AND texts.body IS NOT NULL
    SQL
    rows.flat_map do |row|
      company_id = row["scope_type"] == "Project" ? company_of_project(row["scope_id"].to_i) : row["scope_id"].to_i
      integration_id = default_slack_integration_id(company_id)
      next [] unless integration_id

      row["body"].scan(INSTRUCTION_CHANNEL).flatten.uniq.map { |channel| [ integration_id, channel ] }
    end
  end

  def bind_chat_triggers
    MigrationBinding.where(event_type: CHAT).find_each do |binding|
      filter = binding.filter_predicate.to_h
      conversation = named_conversation(binding, filter)
      if conversation
        bind(binding, conversation, enabled: binding.enabled)
        @counts["triggers_bound"] += 1
        next
      end

      fired = fired_conversations(binding)
      if fired.empty?
        bind(binding, nil, enabled: false)
        @counts["triggers_needing_a_channel"] += 1
        next
      end

      bind(binding, fired.first, enabled: binding.enabled)
      fired.drop(1).each_with_index { |other, index| copy(binding, other, index + 2) }
      @counts["triggers_split"] += 1
    end
  end

  def named_conversation(binding, filter)
    channel = filter["channel"]
    return nil unless channel.is_a?(String) && channel.present?

    company_conversations(binding, filter["provider"]).find_by(external_id: channel)
  end

  # The channels a trigger with no channel actually fired from, most used first.
  def fired_conversations(binding)
    rows = connection.select_all(<<~SQL.squish).to_a
      SELECT trigger_events.data->>'integration_id' AS integration_id, trigger_events.data->>'channel' AS channel,
             COUNT(*) AS uses
      FROM trigger_dispatches
      JOIN trigger_events ON trigger_events.id = trigger_dispatches.trigger_event_id
      WHERE trigger_dispatches.trigger_binding_id = #{binding.id.to_i}
      GROUP BY 1, 2
      ORDER BY uses DESC, channel
    SQL
    scope = company_conversations(binding, binding.filter_predicate.to_h["provider"])
    rows.filter_map { |row| scope.find_by(integration_id: row["integration_id"].to_i, external_id: row["channel"]) }.uniq
  end

  def company_conversations(binding, provider)
    company_id = company_of_project(binding.project_id)
    MigrationConversation.where(provider: provider.to_s, integration_id: MigrationIntegration.where(company_id: company_id).select(:id))
                         .where.not(kind: "direct")
                         .where(id: MigrationConnection.where(company_id: company_id).select(:chat_conversation_id))
  end

  def bind(binding, conversation, enabled:)
    binding.update_columns(chat_conversation_id: conversation&.id, enabled: enabled,
                           filter_predicate: conditions(binding.filter_predicate, conversation), updated_at: Time.current)
  end

  def copy(binding, conversation, number)
    attributes = binding.attributes.except("id", "created_at", "updated_at")
    workflow_name = MigrationWorkflow.where(id: binding.workflow_id).pick(:name)
    MigrationBinding.create!(attributes.merge(
      "name" => "#{binding.name.presence || workflow_name} (#{number})",
      "chat_conversation_id" => conversation.id,
      "filter_predicate" => conditions(binding.filter_predicate, conversation)
    ))
    @counts["trigger_copies"] += 1
  end

  # The trigger's conditions without any place in them, plus the copy of its
  # channel the previous release still matches on.
  def conditions(filter, conversation)
    kept = filter.to_h.reject { |key, _| ROUTING_ROOTS.any? { |root| key == root || key.start_with?("#{root}.") } }
    conversation ? kept.merge("channel" => conversation.external_id) : kept
  end

  def connect(conversation, company_id)
    connection = MigrationConnection.find_or_initialize_by(chat_conversation_id: conversation.id, company_id: company_id)
    return unless connection.new_record?

    connection.save!
    @counts["#{conversation.provider}_channels_connected"] += 1
  end

  def slack_integrations_by_id
    @slack_integrations_by_id ||= MigrationIntegration.where(provider: "slack").index_by(&:id)
  end

  # The install a company's Slack messages went through when none is named:
  # an active one before an inactive one, company-wide before project-bound, oldest first.
  def default_slack_integration_id(company_id)
    @default_slack ||= slack_integrations_by_id.values
                                               .sort_by { |i| [ i.status == "active" ? 0 : 1, i.project_id ? 1 : 0, i.id ] }
                                               .group_by(&:company_id).transform_values { |list| list.first.id }
    @default_slack[company_id]
  end

  def company_of_project(project_id)
    @project_companies ||= MigrationProject.pluck(:id, :company_id).to_h
    @project_companies[project_id]
  end
end
