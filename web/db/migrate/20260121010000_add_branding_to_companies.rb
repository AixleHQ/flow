# frozen_string_literal: true

class AddBrandingToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :display_name, :string
    add_column :companies, :logo_url, :string
    add_column :companies, :primary_color, :string, default: '#4785FF'
    add_column :companies, :secondary_color, :string, default: '#bb9af7'
  end
end
