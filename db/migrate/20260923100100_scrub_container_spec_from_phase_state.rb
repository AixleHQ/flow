# frozen_string_literal: true

# Phase state and runtime-operation results must not hold the create phase's
# container spec — env vars carrying decrypted vendor API keys, per-session keys
# and the prompt. ContainerService does not return it; this removes what earlier
# sessions left behind. Irreversible by design.
class ScrubContainerSpecFromPhaseState < ActiveRecord::Migration[8.1]
  KEYS = %w[env_vars cmd host_config exposed_ports labels working_dir].freeze

  def up
    keys = "ARRAY[#{KEYS.map { |key| connection.quote(key) }.join(', ')}]::text[]"

    execute <<~SQL.squish
      UPDATE session_admissions SET phase_state = phase_state - #{keys}
      WHERE phase_state ?| #{keys}
    SQL
    execute <<~SQL.squish
      UPDATE session_runtime_operations SET result = result - #{keys}
      WHERE result ?| #{keys}
    SQL
  end

  def down; end
end
