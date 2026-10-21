# frozen_string_literal: true

module FeatureFlags
  # Every change to a flag's runtime values, made by a super admin from
  # /admin/feature_flags. Each write takes the admin and a reason, changes the
  # rows and inserts exactly one Audit in one transaction, and bumps the version
  # token only once that transaction has committed: a process that reloads on
  # the bump must find the change, and a write that failed must not cost every
  # process a reload.
  #
  # Refusals raise WriteRefused (EnvLocked for a flag FEATURE_<KEY> decides)
  # before anything is written.
  module Admin
    AUDIT_ACTIONS = %w[global_set global_cleared override_set override_removed turned_off_everywhere pruned]
                    .to_h { |action| [ action.to_sym, "feature_flag.#{action}" ] }.freeze

    class << self
      def set_global(key, enabled, actor:, reason:, request: nil)
        boolean!(enabled)
        write(key, :global_set, actor:, reason:, request:) do |flag|
          previous = flag.enabled
          flag.update!(enabled: enabled)
          { "enabled" => [ previous, enabled ] }
        end
      end

      # Back to the declared default.
      def clear_global(key, actor:, reason:, request: nil)
        write(key, :global_cleared, actor:, reason:, request:) do |flag|
          previous = flag.enabled
          flag.update!(enabled: nil)
          { "enabled" => [ previous, nil ] }
        end
      end

      def set_override(key, company, enabled, actor:, reason:, request: nil)
        boolean!(enabled)
        raise WriteRefused, "Choose a company" if company.nil?

        write(key, :override_set, actor:, reason:, request:, company:, company_scoped: true) do |flag, text|
          override = flag.overrides.find_or_initialize_by(company: company)
          previous = override.new_record? ? nil : override.enabled
          override.update!(enabled: enabled, reason: text, created_by: actor)
          { "enabled" => [ previous, enabled ] }
        end
      end

      def remove_override(key, company, actor:, reason:, request: nil)
        write(key, :override_removed, actor:, reason:, request:, company:, create_row: false) do |flag|
          override = flag.overrides.find_by(company: company)
          raise WriteRefused, "#{company&.name || 'That company'} has no override for #{key}" if override.nil?

          override.destroy!
          { "enabled" => [ override.enabled, nil ] }
        end
      end

      # Company overrides beat the global value, so turning global off alone
      # leaves every company turned on by override on. The removed overrides go
      # into the audit so they can be put back.
      def turn_off_everywhere(key, actor:, reason:, request: nil)
        write(key, :turned_off_everywhere, actor:, reason:, request:) do |flag|
          previous = flag.enabled
          removed = removed_overrides(flag)
          flag.overrides.delete_all
          flag.update!(enabled: false)
          { "enabled" => [ previous, false ], "overrides" => removed }
        end
      end

      # Deletes the rows of a key the registry no longer declares.
      def prune(key, actor:, reason:, request: nil)
        write(key, :pruned, actor:, reason:, request:, declared: false, create_row: false) do |flag|
          changes = { "key" => flag.key, "enabled" => [ flag.enabled, nil ], "overrides" => removed_overrides(flag) }
          flag.destroy!
          changes
        end
      end

      private

      def write(key, action, actor:, reason:, request:, company: nil, company_scoped: false, declared: true, create_row: true)
        key = key.to_s
        text = reason.to_s.strip
        raise WriteRefused, "A reason is required" if text.empty?

        declared ? check_writable!(key, company_scoped:) : check_orphaned!(key)

        audit = FeatureFlag.transaction do
          flag = create_row ? find_or_create_row(key) : FeatureFlag.lock.find_by(key: key)
          raise WriteRefused, "#{key} has no rows" if flag.nil?

          changes = yield(flag, text)
          flag.update_columns(updated_by_id: actor&.id, updated_at: Time.current) unless flag.destroyed?
          Audit.create!(auditable: flag, associated: company, user: actor, username: actor&.email,
                        action: AUDIT_ACTIONS.fetch(action), audited_changes: changes, comment: text,
                        remote_address: request&.remote_ip, request_uuid: request&.uuid)
        end

        # Deferred to the outermost commit when a caller holds a transaction, and
        # dropped if that rolls back.
        ActiveRecord.after_all_transactions_commit do
          log(audit, key)
          FeatureFlags.version_token.bump
        end
        audit
      rescue ActiveRecord::RecordInvalid => e
        raise WriteRefused, e.record.errors.full_messages.to_sentence
      end

      def check_writable!(key, company_scoped:)
        raise WriteRefused, "#{key} is not declared in config/feature_flags.yml" unless FeatureFlags.registry.declared?(key)

        definition = FeatureFlags.registry.fetch(key)
        raise WriteRefused, "#{key} is global: it has no company overrides" if company_scoped && definition.global?
        raise EnvLocked.new(key, definition.env_var) unless FeatureFlags.env_source.value_for(key).nil?
      end

      def check_orphaned!(key)
        raise WriteRefused, "#{key} is declared in config/feature_flags.yml: only undeclared rows are pruned" if FeatureFlags.registry.declared?(key)
      end

      # The lock serializes writes to one flag, so each audit's old value is the
      # value the write replaced.
      def find_or_create_row(key)
        FeatureFlag.lock.find_by(key: key) || FeatureFlag.transaction(requires_new: true) { FeatureFlag.create!(key: key) }
      rescue ActiveRecord::RecordNotUnique
        FeatureFlag.lock.find_by!(key: key)
      end

      def removed_overrides(flag)
        flag.overrides.includes(:company).order(:company_id).map do |override|
          { "company_id" => override.company_id, "company" => override.company&.name, "enabled" => override.enabled,
            "reason" => override.reason, "created_by_id" => override.created_by_id }
        end
      end

      def boolean!(enabled)
        raise WriteRefused, "The value must be on or off" unless [ true, false ].include?(enabled)
      end

      def log(audit, key)
        Rails.logger.tagged("FeatureFlags", audit.action) do
          Rails.logger.info("#{key} changed by #{audit.username || 'system'}: #{audit.audited_changes.to_json}; " \
                            "reason: #{audit.comment}" + (audit.associated_id ? "; company #{audit.associated_id}" : ""))
        end
      end
    end
  end
end
