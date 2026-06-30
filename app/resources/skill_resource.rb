# frozen_string_literal: true

class SkillResource < ApplicationResource
  attributes :id, :name, :title, :description, :package, :source,
             :source_url, :install_count, :scope_type, :scope_id,
             :created_at, :updated_at

  typelize %w[company project]
  attribute :scope_indicator do |skill|
    skill.scope_indicator
  end

  typelize :string
  attribute :registry_url do |skill|
    skill.registry_url
  end
end
