class RenameSubdomainToEmailDomainInCompanies < ActiveRecord::Migration[8.0]
  def change
    rename_column :companies, :subdomain, :email_domain
  end
end
