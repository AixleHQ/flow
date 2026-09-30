# frozen_string_literal: true

module Trackers
  Issue = Data.define(:id, :key, :url, :title, :description, :type, :status, :assignees, :labels,
                      :revision, :scope_id, :updated_at, :fields) do
    include Value
  end
end
