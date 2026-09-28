# frozen_string_literal: true

# Deployment providers were provisioned with `name` set to a humanised kind
# ("Totp", "Magic link"). That froze a label into every installation's data, so
# renaming a method in code would only affect installations created afterwards.
#
# The label now lives in IdentityProvider::KIND_LABELS and `name` stays blank for
# deployment providers. This clears the ones already written.
class ClearFrozenProviderLabels < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE identity_providers SET name = NULL WHERE scope = 'deployment'
    SQL
  end

  def down
    # Deliberately irreversible in data terms: the labels are derived now, and
    # restoring a frozen copy of them would reintroduce the problem.
    raise ActiveRecord::IrreversibleMigration
  end
end
