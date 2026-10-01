# frozen_string_literal: true

class ProjectTrackerResource < ApplicationResource
  attributes :id, :handle, :name, :provider, :external_scope_id, :primary, :access, :status, :integration_id,
             :created_at, :updated_at

  typelize :string
  attribute :integration_name do |tracker|
    tracker.integration.name
  end

  typelize :boolean
  attribute :usable do |tracker|
    tracker.usable?
  end

  typelize :boolean
  attribute :mentions_recognized do |tracker|
    tracker.recognizes_mentions?
  end
end
