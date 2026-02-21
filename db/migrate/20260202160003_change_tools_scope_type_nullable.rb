# frozen_string_literal: true

class ChangeToolsScopeTypeNullable < ActiveRecord::Migration[7.2]
  def change
    change_column_null :tools, :scope_type, true
  end
end
