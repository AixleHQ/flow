# frozen_string_literal: true

# The trial a company is on, in days, and the admin's way to set the day it ends
# (Company#trial_last_day). The value is read from the company rather than the
# attribute, which is blank until an operator sets it.
class CompanyTrialField < Administrate::Field::Base
  def trialing? = resource&.billing_trialing?

  def last_day = Billing::Trial.last_day(resource).strftime("%B %-d, %Y")

  def days_left = Billing::Trial.days_left(resource)
end
