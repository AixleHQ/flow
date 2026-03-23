# frozen_string_literal: true

class IntegrationSerializer < ApplicationSerializer
  attributes :id, :name, :provider, :status, :settings,
             :created_at, :updated_at, :github_url, :project_id, :scope

  belongs_to :connected_by, serializer: UserSerializer

  def scope
    object.project_id.present? ? "project" : "company"
  end

  def github_url
    return nil unless object.github?

    installation_id = object.installation_id
    return nil if installation_id.blank?

    account_type = object.settings&.dig("account_type")
    if account_type == "Organization"
      "https://github.com/organizations/#{object.name}/settings/installations/#{installation_id}"
    else
      "https://github.com/settings/installations/#{installation_id}"
    end
  end
end
