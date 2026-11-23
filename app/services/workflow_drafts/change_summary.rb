# frozen_string_literal: true

module WorkflowDrafts
  # The difference between the live workflow and its draft as a list an agent can
  # read, from the two snapshots WorkflowDrafts.changes returns: workflow fields,
  # then steps matched by id (a step the draft added has a "new-…" id).
  module ChangeSummary
    WORKFLOW_FIELDS = %w[name description runner_id].freeze
    IGNORED_STEP_FIELDS = %w[id sub_steps position].freeze
    SUB_STEP_FIELDS = %w[name instructions required].freeze

    module_function

    def call(live, draft)
      workflow_changes(live, draft) + step_changes(Array(live["steps"]), Array(draft["steps"]))
    end

    def workflow_changes(live, draft)
      changes = WORKFLOW_FIELDS.filter_map do |field|
        next if live[field] == draft[field]

        { "change" => "workflow_changed", "field" => field, "before" => live[field], "after" => draft[field] }
      end
      config_before = live["config"] || {}
      config_after = draft["config"] || {}
      (config_before.keys | config_after.keys).sort.each do |key|
        next if config_before[key] == config_after[key]

        changes << { "change" => "workflow_changed", "field" => "config.#{key}",
                     "before" => config_before[key], "after" => config_after[key] }
      end
      changes
    end

    def step_changes(live_steps, draft_steps)
      live_by_id = live_steps.index_by { |step| step["id"].to_s }
      draft_ids = draft_steps.map { |step| step["id"].to_s }.to_set
      changes = live_steps.reject { |step| draft_ids.include?(step["id"].to_s) }
                          .map { |step| { "change" => "step_removed", "step" => step["name"], "step_id" => step["id"] } }

      draft_steps.each_with_index do |step, index|
        before = live_by_id[step["id"].to_s]
        unless before
          changes << { "change" => "step_added", "step" => step["name"], "position" => index + 1 }
          next
        end

        fields = field_changes(before, step, before.keys | step.keys, IGNORED_STEP_FIELDS)
        fields["position"] = { "before" => live_steps.index(before) + 1, "after" => index + 1 } if live_steps.index(before) != index
        sub_steps = sub_step_changes(Array(before["sub_steps"]), Array(step["sub_steps"]))
        next if fields.empty? && sub_steps.empty?

        change = { "change" => "step_changed", "step" => step["name"], "step_id" => step["id"] }
        change["fields"] = fields if fields.any?
        change["sub_steps"] = sub_steps if sub_steps.any?
        changes << change
      end
      changes
    end

    def sub_step_changes(live_subs, draft_subs)
      live_by_id = live_subs.index_by { |sub| sub["id"].to_s }
      draft_ids = draft_subs.map { |sub| sub["id"].to_s }.to_set
      changes = live_subs.reject { |sub| draft_ids.include?(sub["id"].to_s) }
                         .map { |sub| { "change" => "removed", "name" => sub["name"] } }
      draft_subs.each do |sub|
        before = live_by_id[sub["id"].to_s]
        next changes << { "change" => "added", "name" => sub["name"] } unless before

        fields = field_changes(before, sub, SUB_STEP_FIELDS, [])
        changes << { "change" => "changed", "name" => sub["name"], "fields" => fields } if fields.any?
      end
      changes
    end

    def field_changes(before, after, fields, ignored)
      (fields - ignored).sort.each_with_object({}) do |field, result|
        result[field] = { "before" => before[field], "after" => after[field] } if before[field] != after[field]
      end
    end
  end
end
