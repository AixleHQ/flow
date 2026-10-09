# frozen_string_literal: true

module Billing
  # The one place this application talks to Stripe.
  #
  # An adapter rather than ::Stripe calls scattered through the billing code: the
  # tests below it drive a fake of this, never the vendor's classes, and the
  # decision "is Stripe even configured here" is asked once rather than at every
  # call site. Outside the hosted product nothing here is ever reached.
  #
  # NOT Billing::Stripe: a module of that name would make every bare `Stripe`
  # inside Billing::Meter::Stripe resolve to it rather than to the gem.
  class StripeClient
    class Error < StandardError; end

    # Stripe holds no object by that id — a subscription deleted in the
    # dashboard, or test data that has been cleared.
    class NotFound < Error; end

    EVENT_NAME = "queue_minutes"

    # Every write carries one. Capacity is replayed from a ledger after a failed
    # send, and a replay that bills twice is worse than one that never lands.
    def self.idempotency_key(*parts) = parts.join(":")

    def configured?
      settings.secret_key.present? && settings.price_id.present?
    end

    # Nil until a card is added. The company row holds the id; this makes one.
    def create_customer(company:, email:)
      api do
        ::Stripe::Customer.create(
          { email: email, name: company.name, metadata: { company_id: company.id.to_s } },
          request_options
        )
      end
    end

    # Stripe-hosted card entry. A subscription on the metered price rather than a
    # one-off charge: capacity is continuous, and the price is what turns the
    # meter's queue-minutes into money.
    #
    # ADAPTIVE PRICING OFF. Left on, Stripe converts the page into the visitor's
    # local currency from their IP — a customer in Jakarta was quoted rupiah at
    # Stripe's own rate, which is a second price nobody here set and nobody here
    # can reconcile against the queue-minutes we metered. Everyone is billed in
    # the currency the price is denominated in. Set here rather than in the
    # dashboard so it is version-controlled and survives a setting somebody
    # changes.
    def create_checkout_session(company:, customer_id:, success_url:, cancel_url:)
      api do
        ::Stripe::Checkout::Session.create(
          {
            mode: "subscription",
            customer: customer_id,
            line_items: [ { price: settings.price_id } ],
            adaptive_pricing: { enabled: false },
            success_url: success_url,
            cancel_url: cancel_url,
            metadata: { company_id: company.id.to_s }
          },
          request_options
        )
      end
    end

    def retrieve_subscription(subscription_id:)
      api { ::Stripe::Subscription.retrieve(subscription_id, request_options) }
    end

    # A card a customer pays an outstanding invoice with becomes the one the
    # subscription charges next. Off by default, and Checkout cannot set it, so
    # without this a customer who fixed a failed payment fails again next month.
    def adopt_subscription(subscription_id:)
      api do
        ::Stripe::Subscription.update(
          subscription_id,
          { payment_settings: { save_default_payment_method: "on_subscription" } },
          request_options
        )
      end
    end

    # Now, not at the period's end: capacity is billed in arrears for every hour
    # it is offered, so the rest of a period is not something already paid for,
    # and running it out bills workers nobody wants. `invoice_now` puts the
    # minutes already metered on a final invoice; an hour the meter has not sent
    # yet is never invoiced.
    def cancel_subscription(subscription_id:, reason:, comment:)
      params = { invoice_now: true }
      details = { feedback: reason, comment: comment }.compact_blank
      params[:cancellation_details] = details if details.any?

      api { ::Stripe::Subscription.cancel(subscription_id, params, request_options) }
    end

    # Only for a cancellation scheduled at the period's end, which the
    # application no longer makes.
    def resume_subscription(subscription_id:)
      api { ::Stripe::Subscription.update(subscription_id, { cancel_at_period_end: false }, request_options) }
    end

    # What a worker-minute costs, as the price on the subscription says.
    def retrieve_price
      api { ::Stripe::Price.retrieve(settings.price_id, request_options) }
    end

    # Stripe answers a repeated identifier with a 400 carrying neither a code nor
    # a param, so the message is the only signal there is. Matching it is
    # unpleasant and the failure direction is safe: a message that changes makes
    # the hour look failed, it is replayed, Stripe refuses it again, and after the
    # replay window it is abandoned. Noise, never a second bill.
    ALREADY_RECORDED = /already exists with identifier/i

    # One hour of one company's capacity, in queue-minutes. `identifier` is what
    # makes a replayed hour land once: Stripe refuses a second event carrying an
    # identifier it has already seen, and that refusal means "recorded", not
    # "failed" — so it is answered with :duplicate rather than an exception.
    def send_meter_event(customer_id:, minutes:, occurred_at:, identifier:)
      api do
        begin
          ::Stripe::Billing::MeterEvent.create(
            {
              event_name: EVENT_NAME,
              identifier: identifier,
              timestamp: occurred_at.to_i,
              payload: { stripe_customer_id: customer_id, value: minutes.to_s }
            },
            request_options
          )
        rescue ::Stripe::InvalidRequestError => e
          raise unless e.message.to_s.match?(ALREADY_RECORDED)

          :duplicate
        end
      end
    end

    # Raises unless the body was signed by Stripe with our endpoint's secret. An
    # unverified webhook is an open door to anyone who can guess the URL.
    def construct_event(payload:, signature:)
      raise Error, "no webhook secret configured" if settings.webhook_secret.blank?

      ::Stripe::Webhook.construct_event(payload, signature, settings.webhook_secret)
    rescue ::Stripe::SignatureVerificationError, JSON::ParserError => e
      raise Error, e.message
    end

    private

    def settings
      ::Settings.stripe || Hashie::Mash.new
    end

    def request_options
      { api_key: settings.secret_key }
    end

    # One error class out of this adapter, so callers are not written against the
    # vendor's exception tree.
    def api
      raise Error, "Stripe is not configured" unless configured?

      yield
    rescue ::Stripe::InvalidRequestError => e
      raise (e.code == "resource_missing" ? NotFound : Error), "#{e.class.name.demodulize}: #{e.message}"
    rescue ::Stripe::StripeError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end
  end
end
