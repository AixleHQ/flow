# frozen_string_literal: true

# A pull_request_* write can be made as a named member instead of the connection
# (docs/design/bitbucket-integration.md §4.12). The ledger records who: nil is the
# connection. The review tool's refusal to approve a pull request the same identity
# opened reads it.
class AddActingUserToPullRequestOperations < ActiveRecord::Migration[8.1]
  def change
    add_reference :pull_request_operations, :acting_user, foreign_key: { to_table: :users, on_delete: :nullify },
                                                          index: false
  end
end
