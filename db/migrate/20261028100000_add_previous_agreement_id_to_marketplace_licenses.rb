# frozen_string_literal: true

class AddPreviousAgreementIdToMarketplaceLicenses < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_licenses, :previous_agreement_id, :string
  end
end
