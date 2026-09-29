# frozen_string_literal: true

# The SCIM request's tenant, set by the token authenticator and read by the
# controllers (CAP-6).
#
# CurrentAttributes rather than a thread-local: Rails resets it between requests,
# which is exactly the property that matters here — a leaked configuration would
# scope one customer's directory sync to another customer's company.
class ScimCurrent < ActiveSupport::CurrentAttributes
  attribute :configuration

  def company
    configuration&.company
  end
end
