# frozen_string_literal: true

# Which of the two products this installation is.
#
# The difference that matters is who owns the capacity number. In a self-hosted
# installation the customer buys their own capacity and sets it themselves, so a
# company admin may raise their own limit. In the hosted product that number is
# what we invoice for, so only a platform administrator may move it.
#
# UNSET READS AS HOSTED. Getting this wrong in one direction lets a customer
# grant themselves capacity they have not paid for; in the other it only means a
# self-hosted operator sets the number from the admin, which they already have.
module Deployment
  SELF_HOSTED = "self_hosted"
  HOSTED = "hosted"

  class << self
    def mode
      raw = Settings.deployment&.mode.to_s.strip
      return SELF_HOSTED if raw == SELF_HOSTED

      HOSTED
    end

    def self_hosted? = mode == SELF_HOSTED
    def hosted? = mode == HOSTED
  end
end
