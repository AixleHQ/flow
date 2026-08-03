# frozen_string_literal: true

class SkillResource < ApplicationResource
  attributes :id, :name, :title, :description, :package, :source,
             :source_url, :install_count, :scope_type, :scope_id,
             :created_at, :updated_at

  typelize %w[company project]
  attribute :scope_indicator do |skill|
    skill.scope_indicator
  end

  # Registry vs hand-written. The UI needs it because a manual skill has no
  # registry page, cannot be re-installed by the CLI, and is labelled as ours.
  typelize %w[registry manual]
  attribute :origin do |skill|
    skill.origin.to_s
  end

  # Null for a manual skill — there is nothing upstream to link to.
  typelize :string?
  attribute :registry_url do |skill|
    skill.registry_url
  end
end
