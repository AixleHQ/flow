# frozen_string_literal: true

class DefaultCompaniesToActiveBilling < ActiveRecord::Migration[8.1]
  # `trialing` was the wrong default. The free allowance belongs to the one path
  # where a stranger signs themselves up; every other way a company comes into
  # being — the admin, the seeds, the factories — is somebody deciding, and a
  # company created that way silently stopping after a hundred queue-hours is a
  # surprise nobody would connect to this.
  #
  # So the default is what an operator means, and WorkspaceOnboardingForm says
  # `trialing` out loud for the one case that is on a trial.
  def up
    change_column_default :companies, :billing_state, from: "trialing", to: "active"
  end

  def down
    change_column_default :companies, :billing_state, from: "active", to: "trialing"
  end
end
