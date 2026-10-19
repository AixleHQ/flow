# frozen_string_literal: true

# The pre-breakdown aggregate. Nothing has read or written it since #508.
#
# Dropped without an `ignored_columns` release first, by choice: a pod still on
# the previous release knows the column and puts it in every INSERT, so a
# Cursor, Codex, Grok or Kiro session that ends between DB Migrate and the end
# of the rollout loses its usage row. OTLP usage is unaffected — the
# accumulator's upsert stopped naming the column in #508.
class RemoveTokensFromUsageStatistics < ActiveRecord::Migration[8.1]
  def change
    remove_column :usage_statistics, :tokens, :bigint, default: 0, null: false
  end
end
