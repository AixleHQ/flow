# frozen_string_literal: true

# Which product this installation is, which decides two things: who owns the
# capacity number, and who is billed for it.
#
#   self_hosted      the customer runs it and pays nobody for it. Their admin
#                    sets the capacity, and nothing is metered.
#   saas             we host it and invoice per organisation through Stripe.
#                    Only a platform administrator moves the number.
#   aws_marketplace  the customer runs it in their own AWS account and AWS
#                    invoices them. Their admin sets the capacity, and the
#                    installation meters the whole of it to AWS.
#
# UNSET READS AS SAAS. The dangerous direction is a hosted installation whose
# variable was forgotten: a company admin would grant themselves capacity we
# invoice nobody for. The other direction only means a self-hosted operator sets
# the number from the admin, which they already have. Development and test set
# `self_hosted` explicitly in their own settings files.
module Deployment
  SELF_HOSTED = "self_hosted"
  SAAS = "saas"
  AWS_MARKETPLACE = "aws_marketplace"

  MODES = [ SELF_HOSTED, SAAS, AWS_MARKETPLACE ].freeze

  class << self
    def mode
      raw = Settings.deployment&.mode.to_s.strip.downcase
      return raw if MODES.include?(raw)

      if raw.present?
        Rails.logger.error(
          "[Deployment] DEPLOYMENT_MODE=#{raw.inspect} is not one of #{MODES.join(', ')}; reading as #{SAAS}"
        )
      end
      SAAS
    end

    # Whether a stranger may sign a company up here, which also decides whether
    # the page that sells it exists. Hosted only — elsewhere a workspace is made
    # by the operator or bought through AWS — and off until an operator says
    # otherwise, because the screens ship before the product is ready to take
    # strangers and a half-open door is worse than a closed one.
    def self_serve_signup? = saas? && Settings.registration&.enabled == true

    def self_hosted? = mode == SELF_HOSTED
    def saas? = mode == SAAS
    def aws_marketplace? = mode == AWS_MARKETPLACE

    # Who may set a company's own limit. The customer owns the number wherever
    # they are the one buying the capacity; where we invoice for it, they do not.
    def customer_owns_capacity? = !saas?

    # A company with no limit is unbounded, and "unlimited" has no encoding in a
    # metering record — AWS Marketplace takes a quantity or nothing. So where the
    # installation meters itself to AWS, every company must carry a number.
    def requires_bounded_companies? = aws_marketplace?

    # Whether capacity is charged for at all. A company admin may raise their own
    # limit wherever it is, because raising it raises what they pay; they may
    # never clear it, because an unbounded company is one nobody is invoiced for.
    # Only a platform administrator may leave a company without a number, and
    # only where AWS is not the one counting.
    def bills_capacity? = !self_hosted?

    def misconfigured?
      raw = Settings.deployment&.mode.to_s.strip
      raw.present? && !MODES.include?(raw.downcase)
    end
  end
end
