# frozen_string_literal: true

module Trackers
  module Jira
    # Erases what Aixle keeps about an Atlassian account that has been closed:
    # the account id and the name or email next to it, wherever a tracker
    # record holds them. A person object becomes "Former user"; an assignee
    # change loses both ends' ids.
    #
    # Text that merely mentions the person (an issue body copied into a task, an
    # agent's transcript) is not traced back to an account id and is not erased.
    module PersonalDataErasure
      FORMER = "Former user"
      PERSON_KEYS = %w[id accountId account_id].freeze
      NAME_KEYS = %w[name displayName display_name author email emailAddress].freeze

      module_function

      def erase!(account_id)
        id = account_id.to_s
        return if id.blank?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(id)}%"
        TriggerEvent.where(source: TriggerBinding::TRACKER_SOURCE).where("data::text LIKE ?", like).find_each do |event|
          event.update_columns(data: scrub(event.data, id))
        end
        WorkflowRun.where("shared_context::text LIKE ?", like).find_each do |run|
          run.update_columns(shared_context: scrub(run.shared_context, id))
        end
        TrackerOperation.where("result::text LIKE ? OR change::text LIKE ?", like, like).find_each do |operation|
          operation.update_columns(result: scrub(operation.result, id), change: scrub(operation.change, id))
        end
        TrackerDelivery.where("notifications::text LIKE ?", like).delete_all
        Integration.where(provider: "jira").where("settings::text LIKE ?", like).find_each do |integration|
          integration.update_columns(settings: forget_identity(integration.settings.to_h, id))
        end
        TrackerAccount.where(provider: "jira", account_id: id).update_all(status: "closed", closed_at: Time.current)
      end

      def scrub(value, id)
        case value
        when Hash then scrub_hash(value, id)
        when Array then value.map { |item| scrub(item, id) }
        when String then value == id ? nil : value
        else value
        end
      end

      def scrub_hash(hash, id)
        if PERSON_KEYS.any? { |key| hash[key].to_s == id }
          hash.to_h { |key, v| [ key, person_value(key, v, id) ] }
        elsif hash["from_id"].to_s == id || hash["to_id"].to_s == id
          side = hash["from_id"].to_s == id ? "from" : "to"
          scrubbed = hash.merge("#{side}_id" => nil, side => FORMER)
          scrubbed.to_h { |key, v| [ key, scrub(v, id) ] }
        else
          hash.to_h { |key, v| [ key, scrub(v, id) ] }
        end
      end

      def person_value(key, value, id)
        return nil if PERSON_KEYS.include?(key)
        return FORMER if NAME_KEYS.include?(key)

        scrub(value, id)
      end

      def forget_identity(settings, id)
        return settings unless settings.dig("tracker_identity", "id").to_s == id

        settings.except("tracker_identity", "identity_display_name")
      end
    end
  end
end
