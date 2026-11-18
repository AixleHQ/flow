# frozen_string_literal: true

# docs/design/tenant-usage-report.md §7.2: who besides a superadmin may open the
# platform dashboard, at /dashboard.
class AddDashboardViewerToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :dashboard_viewer, :boolean, null: false, default: false
  end
end
