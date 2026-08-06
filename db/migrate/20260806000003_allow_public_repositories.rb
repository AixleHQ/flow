# frozen_string_literal: true

# Public repositories are attached without an integration: they are cloned
# anonymously (no credentials), so there is no installation or token to hang
# them off. Everything that used to be guaranteed by the NOT NULL — provider,
# clone url, read/write capability — is now derived in Repository from the
# clone url instead.
class AllowPublicRepositories < ActiveRecord::Migration[8.1]
  def change
    change_column_null :repositories, :integration_id, true
  end
end
