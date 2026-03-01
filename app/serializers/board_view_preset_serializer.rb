# frozen_string_literal: true

class BoardViewPresetSerializer < ApplicationSerializer
  attributes :id, :name, :filters, :user_id, :shared, :created_at, :updated_at
end
