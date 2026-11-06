# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §9.2, the retry after a lost
# `POST /runner/v1/token` response: a pair names the refresh credential whose
# spend issued it, so that a spent refresh token presented again can tell
# whether that pair was ever used. The access token's first use goes into the
# existing `used_at`. The link only matters within the retry window, so
# deleting the credential it names clears it rather than cascading down the
# family's chain of pairs to the live one.
class AddRotatedFromToRunnerCredentials < ActiveRecord::Migration[8.1]
  def change
    add_reference :runner_credentials, :rotated_from,
                  foreign_key: { to_table: :runner_credentials, on_delete: :nullify }
  end
end
