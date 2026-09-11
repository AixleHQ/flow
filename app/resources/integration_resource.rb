# frozen_string_literal: true

class IntegrationResource < ApplicationResource
  attributes :id, :name, :provider, :status, :project_id, :created_at, :updated_at

  # settings is a free-form jsonb blob; column inference can only see `unknown`.
  # Expose it as an explicit attribute so the keyless `typelize` annotation applies
  # (the keyed form is gated by Typelizer.enabled? at load time and is unreliable).
  #
  # `settings` reaches the browser whole, so nothing secret may be written into
  # it — tokens, app secrets, authorization headers and raw provider errors all
  # belong elsewhere. The Azure writers keep to identity and status; the two
  # keys below are surfaced explicitly rather than left for the frontend to dig
  # out of the blob.
  typelize "Record<string, unknown>"
  attribute :settings do |integration|
    integration.settings
  end

  # ----- Azure DevOps -----
  #
  # Read through the model's accessors, which prefer the authoritative
  # installation row over the settings copy: a stale or edited settings blob
  # must never widen what the UI reports as connected.

  typelize :string?
  attribute :azure_auth_mode do |integration|
    integration.azure_devops? ? integration.azure_auth_mode : nil
  end

  typelize :string?
  attribute :azure_organization do |integration|
    integration.azure_devops? ? integration.azure_organization_slug : nil
  end

  typelize :string?
  attribute :azure_project_name do |integration|
    integration.azure_devops? ? integration.azure_project_name : nil
  end

  typelize :string?
  attribute :azure_project_id do |integration|
    integration.azure_devops? ? integration.azure_project_id : nil
  end

  typelize :string?
  attribute :azure_identity do |integration|
    integration.azure_devops? ? integration.settings&.dig("identity_display_name") : nil
  end

  typelize "string[]"
  attribute :azure_capabilities do |integration|
    integration.azure_devops? ? integration.azure_enabled_capabilities : []
  end

  typelize :string?
  attribute :azure_url do |integration|
    next nil unless integration.azure_devops?

    slug = integration.azure_organization_slug
    slug.present? ? "https://dev.azure.com/#{slug}" : nil
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

  typelize :string?
  attribute :slack_request_url do |integration|
    integration.slack? ? integration.settings&.dig("request_url") : nil
  end
end
