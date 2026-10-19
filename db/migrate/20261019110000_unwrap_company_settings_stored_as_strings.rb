# frozen_string_literal: true

# Saving a company in the admin stored its settings as a JSON string of the
# document instead of the document, and every later save quoted it again (fixed
# in Admin::ApplicationController#resource_params). This unwraps the rows already
# saved that way: a string that parses to an object becomes it, anything else
# becomes the column's default of {}. On production, company 1 held its
# object as a string and company 5 held "null".
#
# Idempotent: an unwrapped row is no longer a JSON string.
class UnwrapCompanySettingsStoredAsStrings < ActiveRecord::Migration[8.1]
  class MigCompany < ActiveRecord::Base
    self.table_name = "companies"
  end

  def up
    MigCompany.where("jsonb_typeof(settings) = 'string'").find_each do |company|
      company.update_columns(settings: unwrap(company.settings))
    end
  end

  # Not reversible: a document quoted into a string is never what anyone meant to store.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def unwrap(value)
    value = JSON.parse(value) while value.is_a?(String)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError
    {}
  end
end
