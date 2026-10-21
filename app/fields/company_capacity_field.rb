# frozen_string_literal: true

# A company's session limit, rendered so that its absence is visible.
#
# Absence means two things at once — unbounded, and not billed — and the index
# is the only place both are readable at a glance. It matters only in the hosted
# product: a self-hosted installation invoices nobody, and a Marketplace one
# cannot have an unbounded company at all (SessionConcurrencyLimit refuses it).
class CompanyCapacityField < Administrate::Field::Base
  def limit = data

  def unlimited? = data.blank?

  def unbilled? = unlimited? && Deployment.saas?

  # Never above the number the company already has: the browser would refuse to
  # submit any edit of a company given fewer before the minimum existed.
  def minimum = [ Deployment.minimum_workers, data.presence&.to_i ].compact.min
end
