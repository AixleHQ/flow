# frozen_string_literal: true

module FeatureFlags
  # The cleanup side of a flag's life, behind `bin/rails feature_flags:audit`
  # and `bin/rails feature_flags:prune` (lib/tasks/feature_flags.rake).
  #
  # `report` lists what is due for removal and changes nothing. `prune` deletes
  # the rows of keys config/feature_flags.yml no longer declares, through
  # FeatureFlags::Admin.prune, so each key gets its own `feature_flag.pruned`
  # Audit. Nothing runs prune automatically: an old pod may still check a key
  # whose rows it deletes, and after a rollback the restored declaration would
  # silently fall back to its default. See docs/architecture/feature-flags.md.
  class Lifecycle
    PRUNE_REASON = "feature_flags:prune: no longer declared in config/feature_flags.yml"

    Report = Data.define(:past_remove_by, :same_everywhere, :orphans, :undeclared_env) do
      def empty? = [ past_remove_by, same_everywhere, orphans, undeclared_env ].all?(&:empty?)
    end

    def initialize(registry: FeatureFlags.registry, env: FeatureFlags.env_source)
      @registry = registry
      @env = env
    end

    def report(today: Date.current)
      overview = Overview.new(registry: @registry, env: @env)
      rows = overview.rows

      Report.new(
        past_remove_by: rows.select { |row| row.definition.release? && row.past_remove_by?(today) },
        same_everywhere: rows.select { |row| row.same_everywhere_long?(today) },
        orphans: overview.orphans,
        undeclared_env: @env.undeclared
      )
    end

    # The keys whose rows were deleted. Running it again deletes nothing, and a
    # key an admin pruned from /admin/feature_flags meanwhile is skipped.
    def prune(actor: nil, reason: PRUNE_REASON)
      Overview.new(registry: @registry, env: @env).orphans.filter_map do |orphan|
        Admin.prune(orphan.key, actor: actor, reason: reason)
        orphan.key
      rescue WriteRefused
        nil
      end
    end

    # The audit as `feature_flags:audit` prints it: every category, empty or not.
    def self.describe(report, today: Date.current)
      sections = {
        "Release flags past remove_by" => report.past_remove_by.map do |row|
          "#{row.key} (owner #{row.definition.owner}, remove_by #{row.definition.remove_by})"
        end,
        "Same value for every company for #{Overview::SAME_EVERYWHERE_FOR.inspect}+" => report.same_everywhere.map do |row|
          "#{row.key} = #{row.resolution.value ? 'on' : 'off'} since #{row.same_everywhere_since} " \
            "(owner #{row.definition.owner}, decided by #{row.resolution.source})"
        end,
        "Orphaned rows (keys no longer declared; remove with feature_flags:prune)" => report.orphans.map do |orphan|
          "#{orphan.key} (#{orphan.overrides_count} company override#{'s' unless orphan.overrides_count == 1})"
        end,
        "FEATURE_* variables for undeclared keys (remove them from the environment)" => report.undeclared_env
      }

      lines = [ "Feature flags audit, #{today}" ]
      sections.each do |title, items|
        lines << "" << "#{title}: #{items.size}"
        lines.concat(items.empty? ? [ "  none" ] : items.map { |item| "  #{item}" })
      end
      lines.join("\n")
    end
  end
end
