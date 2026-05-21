# frozen_string_literal: true

class IntegrationResource < ApplicationResource
  attributes :id, :name, :provider, :status, :project_id, :settings, :created_at, :updated_at

  attribute :scope_indicator do |integration|
    integration.project_id.present? ? "project" : "company"
  end

  attribute :installation_id do |integration|
    integration.installation_id
  end

  attribute :github_url do |integration|
    next nil unless integration.github?

    iid = integration.installation_id
    next nil if iid.blank?

    app_slug = Settings.github.app_slug
    if app_slug.present?
      "https://github.com/apps/#{app_slug}/installations/#{iid}"
    else
      "https://github.com/settings/installations/#{iid}"
    end
  end

  attribute :connected_by do |integration|
    { id: integration.connected_by.id, name: integration.connected_by.name }
  end
end
