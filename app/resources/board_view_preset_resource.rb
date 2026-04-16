# frozen_string_literal: true

class BoardViewPresetResource < ApplicationResource
  attributes :id, :name, :filters, :shared, :user_id, :created_at
end
