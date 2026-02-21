class ChangeCompanyIdToNullableInUsers < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :company_id, true
  end
end
