# frozen_string_literal: true

class ScopeMarketplaceLicenseCompanyUniquenessToLive < ActiveRecord::Migration[8.1]
  # One LIVE licence per workspace, not one ever.
  #
  # A workspace keeps the licences it has finished with: which subscription paid
  # for which month is a billing record. The old index did not say that, so an
  # ended licence went on holding its workspace's slot and a customer who
  # cancelled could never subscribe again -- while the product's own screen told
  # them to. Seen for real on 26 October.
  def change
    remove_index :marketplace_licenses, :company_id, unique: true,
                 where: "company_id IS NOT NULL", name: "index_marketplace_licenses_on_company_id"
    add_index :marketplace_licenses, :company_id, unique: true,
              where: "company_id IS NOT NULL AND subscription_state <> 'ended'",
              name: "index_marketplace_licenses_on_company_id"
  end
end
