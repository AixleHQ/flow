# frozen_string_literal: true

class AddPriceToMarketplaceLicenses < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_licenses, :price_per_minute, :decimal, precision: 12, scale: 8
    add_column :marketplace_licenses, :price_currency, :string
  end
end
