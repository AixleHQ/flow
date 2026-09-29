# frozen_string_literal: true

# Keeps a polymorphically scoped row's real tenant columns — project_id and
# company_id — in step with its scope pair. The pair is what the application
# reads and writes; these columns are what the database constrains: foreign keys
# to the project and company, a composite key tying the two together, and a check
# that they agree with the pair (AddTenantColumnsToScopedResources).
module TenantColumns
  extend ActiveSupport::Concern

  included do
    before_validation :sync_tenant_columns
    # Again on save, for writes that skip validation.
    before_save :sync_tenant_columns
  end

  private

  def sync_tenant_columns
    return unless new_record? || will_save_change_to_scope_type? || will_save_change_to_scope_id? || company_id.nil?

    case scope_type
    when "Project"
      self.project_id = scope_id
      self.company_id = scope_id && scoped_project_company_id
    when "Company"
      self.project_id = nil
      self.company_id = scope_id
    else
      self.project_id = nil
      self.company_id = nil
    end
  end

  def scoped_project_company_id
    loaded = self.class.reflect_on_association(:scope) && association(:scope).loaded? && scope
    loaded ? scope.company_id : Project.where(id: scope_id).pick(:company_id)
  end
end
