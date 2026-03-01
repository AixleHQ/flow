# frozen_string_literal: true

class SkillSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :title, :content, :description, :kind,
             :scope_type, :scope_id, :internal,
             :created_at, :updated_at

  def internal
    object.internal?
  end
end
