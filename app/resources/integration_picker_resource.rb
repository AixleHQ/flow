# frozen_string_literal: true

# What a picker needs to attach an integration to a workflow, a step or a new session:
# which one it is (name, provider, and a Coder host to tell alike names apart) and whether
# it works. Nothing secret.
class IntegrationPickerResource < ApplicationResource
  typelize :number
  attribute :id do |integration|
    integration.id
  end

  typelize :string
  attribute :name do |integration|
    integration.name
  end

  typelize :string
  attribute :provider do |integration|
    integration.provider.to_s
  end

  typelize :string
  attribute :status do |integration|
    integration.status.to_s
  end

  typelize "string | null"
  attribute :host do |integration|
    integration.coder? ? integration.coder_host : nil
  end

  # The company's own, or this project's: lists a company-wide one apart from a project's.
  typelize :boolean
  attribute :company_wide do |integration|
    integration.project_id.nil?
  end
end
