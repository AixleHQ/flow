# frozen_string_literal: true

class SkillSerializer < ApplicationSerializer
  attributes :id, :name, :title, :content, :description, :kind,
             :scope_type, :scope_id, :scope_indicator, :internal,
             :created_at, :updated_at

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.internal?
      "internal"
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end

  def internal
    object.internal?
  end
end
