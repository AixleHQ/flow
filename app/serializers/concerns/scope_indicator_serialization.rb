# frozen_string_literal: true

# Shared scope_indicator logic for serializers of scoped resources.
#
# Relies on:
#   - object#scope_indicator   (instance method on the model)
#   - object#name / object#full_name (for override detection)
#   - @instance_options[:project] passed from controller
#
# When a project context is provided, project-scoped records whose name
# also exists at company level are marked as "overrides_company".
module ScopeIndicatorSerialization
  extend ActiveSupport::Concern

  included do
    attributes :scope_indicator
  end

  def scope_indicator
    base = object.scope_indicator
    return base unless base == "project" && company_override?
    "overrides_company"
  end

  private

  def company_override?
    project = @instance_options[:project]
    return false unless project

    lookup_name = object.respond_to?(:full_name) ? object.full_name : object.name
    company_override_names.include?(lookup_name)
  end

  def company_override_names
    cache_key = :"_company_override_names_#{object.class.name}"
    @instance_options[cache_key] ||= begin
      project = @instance_options[:project]
      col = override_name_column
      object.class
            .where(scope_type: "Company", scope_id: project.company_id)
            .pluck(col)
            .to_set
    end
  end

  def override_name_column
    object.respond_to?(:full_name) ? :full_name : :name
  end
end
