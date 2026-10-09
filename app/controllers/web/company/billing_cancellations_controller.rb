# frozen_string_literal: true

# Stopping a subscription now (create), and taking back a cancellation scheduled
# for the end of a period (destroy) — which only companies that cancelled before
# cancelling became immediate still have.
#
# The company is stopped here rather than when `customer.subscription.deleted`
# arrives, so no hour after the click is offered, and billed, while the webhook
# is on its way.
class Web::Company::BillingCancellationsController < Web::Company::ApplicationController
  include HostedBillingOnly

  UNREACHABLE = "We could not reach our payment provider. Nothing has changed — try again in a moment."

  def create
    return refuse("Only a paying workspace has a subscription to cancel.") unless cancellable?
    return refuse("Choose one of the listed reasons.") unless reason_valid?

    # Under the row lock, so a double submit cancels once and mails once: the
    # second request finds the company already stopped and does nothing.
    cancellation = current_company.with_lock { cancel! if cancellable? }
    notify_admins(cancellation) if cancellation

    redirect_to company_settings_billing_path,
                notice: "Your subscription is cancelled. Usage up to now is billed on a final invoice."
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[BillingCancellations] company #{current_company.id}: #{e.message}")
    refuse(UNREACHABLE)
  end

  def destroy
    return redirect_to(company_settings_billing_path) unless current_company.billing_cancellation_scheduled?

    subscription = Billing::SubscriptionState.from(
      client.resume_subscription(subscription_id: current_company.stripe_subscription_id)
    )
    current_company.with_lock do
      current_company.update!(billing_cancels_at: subscription.cancels_at)
      current_company.billing_cancellations.pending.update_all(resumed_at: Time.current)
    end

    redirect_to company_settings_billing_path, notice: "Your subscription continues."
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[BillingCancellations] company #{current_company.id}: #{e.message}")
    refuse(UNREACHABLE)
  end

  private

  def cancellable?
    current_company.billing_active? && current_company.stripe_subscription_id.present?
  end

  # `billing_event_at` too, so a `customer.subscription.updated` from before the
  # cancellation that arrives after it is dropped as stale instead of starting
  # the company again.
  def cancel!
    subscription = Billing::SubscriptionState.from(
      client.cancel_subscription(subscription_id: current_company.stripe_subscription_id,
                                 reason: reason, comment: comment)
    )
    ended_at = subscription.ended_at || Time.current

    current_company.update!(billing_state: "blocked", billing_block_reason: "canceled",
                            billing_cancels_at: ended_at, billing_event_at: ended_at)
    current_company.billing_cancellations.create!(user: current_user, reason: reason, comment: comment,
                                                  cancels_at: ended_at)
  end

  # Every admin, the one who cancelled included: there is no billing contact,
  # and a workspace that stops without the others hearing of it is a support
  # ticket the day it does.
  def notify_admins(cancellation)
    current_company.billing_admins.find_each do |admin|
      BillingMailer.subscription_cancelled(cancellation, admin).deliver_later
    end
  end

  def reason
    params[:reason].presence
  end

  def reason_valid?
    reason.nil? || BillingCancellation::REASONS.include?(reason)
  end

  def comment
    params[:comment].to_s.strip.first(BillingCancellation::COMMENT_MAX).presence
  end

  def client
    @client ||= Billing::StripeClient.new
  end

  def refuse(message)
    redirect_to company_settings_billing_path, alert: message
  end
end
