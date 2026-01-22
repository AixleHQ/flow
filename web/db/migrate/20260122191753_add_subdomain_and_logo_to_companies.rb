class AddSubdomainAndLogoToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Add columns as nullable first
    add_column :companies, :subdomain, :string
    add_column :companies, :auto_accept_users, :boolean, default: false, null: false
    add_column :companies, :logo_data, :text

    change_column_null :companies, :subdomain, false
    add_index :companies, :subdomain, unique: true
  end
end
