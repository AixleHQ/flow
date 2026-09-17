# frozen_string_literal: true

# A company's decision about one provider (AD-4). This is the only thing a
# company admin toggles.
#
# An absent row means DENIED: rows are seeded when a company is created and by
# the backfill migration, so "no row" is never an ambiguous default.
class CompanyAuthPolicy < ApplicationRecord
  belongs_to :company
  belongs_to :identity_provider

  validates :identity_provider_id, uniqueness: { scope: :company_id }

  scope :enabled, -> { where(enabled: true) }
end
