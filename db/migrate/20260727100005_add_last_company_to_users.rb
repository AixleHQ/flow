# frozen_string_literal: true

# Remembers the company a user last acted in, so the switcher choice survives
# logout/session expiry instead of snapping back to the oldest membership.
# Nullable and FK-less on purpose: it is a soft hint, re-validated against
# active memberships on every request, and a deleted company must not block
# deletion or strand the user.
class AddLastCompanyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_company_id, :bigint
  end
end
