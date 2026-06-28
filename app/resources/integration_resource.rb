# frozen_string_literal: true

class IntegrationResource < ApplicationResource
  attributes :id, :name, :provider, :status, :project_id, :created_at, :updated_at

  # settings is a free-form jsonb blob; column inference can only see `unknown`.
  # Expose it as an explicit attribute so the keyless `typelize` annotation applies
  # (the keyed form is gated by Typelizer.enabled? at load time and is unreliable).
  typelize "Record<string, unknown>"
  attribute :settings do |integration|
    integration.settings
  end

  typelize %w[company project]
  attribute :scope_indicator do |integration|
    integration.project_id.present? ? "project" : "company"
  end

  typelize :string?
  attribute :installation_id do |integration|
    integration.installation_id
  end

  typelize :string?
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

  typelize "{ id: number; name: string }"
  attribute :connected_by do |integration|
    { id: integration.connected_by.id, name: integration.connected_by.name }
  end

  typelize :string?
  attribute :coder_url do |integration|
    integration.coder? ? integration.coder_url : nil
  end

  typelize :string?
  attribute :coder_default_template do |integration|
    integration.coder? ? integration.coder_default_template : nil
  end

  typelize :string?
  attribute :coder_machine_prefix do |integration|
    integration.coder? ? integration.coder_machine_prefix : nil
  end

  typelize :number?
  attribute :coder_lock_ttl_minutes do |integration|
    integration.coder? ? integration.coder_lock_ttl_minutes : nil
  end

  attribute :slack_request_url do |integration|
    integration.slack? ? integration.settings&.dig("request_url") : nil
  end
end
