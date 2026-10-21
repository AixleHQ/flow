# frozen_string_literal: true

# One company that is an exception to a company-scoped flag's global value. The
# reason is required: an override nobody can explain is the hardest flag debt
# to clean up.
class FeatureFlagOverride < ApplicationRecord
  belongs_to :feature_flag, inverse_of: :overrides
  belongs_to :company
  belongs_to :created_by, class_name: "User", optional: true

  validates :enabled, inclusion: { in: [ true, false ] }
  validates :reason, presence: true
  validates :company_id, uniqueness: { scope: :feature_flag_id }
  validate :flag_declared_and_company_scoped, on: :create

  private

  def flag_declared_and_company_scoped
    return if feature_flag.nil?

    definition = feature_flag.definition
    if definition.nil?
      errors.add(:feature_flag, "is not declared in config/feature_flags.yml")
    elsif definition.global?
      errors.add(:feature_flag, "is global: it has no company overrides")
    end
  end
end
