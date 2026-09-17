# frozen_string_literal: true

# The ceiling is read from the deployment now, not copied into this row.
#
# The column existed because the value used to select which pool a session
# belonged to, so applying it re-homed live sessions and had to happen in a
# maintenance window — hence a rake task to copy it. It selects nothing any more,
# and a deployed installation has no shell to run that task in, so the copy
# bought only a step nobody could perform. A column that decides nothing is a
# column someone will edit believing it does.
#
# The check constraint has to be rebuilt rather than left: it names the column.
class DropInstallationLimitFromSessionAdmissionPolicies < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :session_admission_policies, name: "valid_session_policy"
    remove_column :session_admission_policies, :installation_limit
    add_check_constraint :session_admission_policies, "id = 1", name: "valid_session_policy"
  end

  def down
    remove_check_constraint :session_admission_policies, name: "valid_session_policy"
    add_column :session_admission_policies, :installation_limit, :integer
    add_check_constraint :session_admission_policies,
      "id = 1 AND (installation_limit IS NULL OR installation_limit > 0)",
      name: "valid_session_policy"
  end
end
