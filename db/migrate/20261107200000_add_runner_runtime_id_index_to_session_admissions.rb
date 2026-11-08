# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §5.3, task 8a: ContainerRuntime::RunnerRuntime
# is not bound to a session, so every runtime call finds its session from the
# admission whose `runtime_id` its container id or cleanup identity is. Only
# runner admissions are looked up that way, so the index covers only them.
class AddRunnerRuntimeIdIndexToSessionAdmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :session_admissions, :runtime_id, where: "runtime_kind = 'ContainerRuntime::RunnerRuntime'",
                                                name: "index_session_admissions_on_runner_runtime_id",
                                                algorithm: :concurrently, if_not_exists: true
  end
end
