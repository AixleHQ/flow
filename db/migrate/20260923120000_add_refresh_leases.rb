# frozen_string_literal: true

# A per-credential refresh lease (RefreshLease): one refresher at a time, and
# never one holding a database transaction open across the provider call.
class AddRefreshLeases < ActiveRecord::Migration[8.1]
  def change
    %i[agent_credentials oauth_credentials].each do |table|
      add_column table, :refresh_lease_until, :datetime
      add_column table, :refresh_lease_token, :string
    end
  end
end
