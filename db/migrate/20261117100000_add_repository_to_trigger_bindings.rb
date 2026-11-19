# frozen_string_literal: true

# docs/design/pull-request-triggers.md §4: a pull-request trigger may listen to
# one repository of its project. Removing the repository removes the triggers
# bound to it: left unbound, one would widen to every repository instead.
class AddRepositoryToTriggerBindings < ActiveRecord::Migration[8.1]
  def change
    add_reference :trigger_bindings, :repository, foreign_key: { on_delete: :cascade }
  end
end
