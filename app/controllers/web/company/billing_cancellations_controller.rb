# frozen_string_literal: true

# Stopping a subscription at the end of the period already under way (create),
# and changing one's mind before that date arrives (destroy).
#
# Only the schedule is ours to set. The company keeps running until Stripe
# reports the subscription deleted, and that webhook is what stops it — so the
# minutes up to the end date are metered and invoiced like any others.
class Web::Company::BillingCancellationsController < Web::Company::ApplicationController
  UNREACHABLE = "We could not reach our payment provider. Nothing has changed — try again in a moment."

  def create
    return refuse("Only a paying workspace has a subscription to cancel.") unless cancellable?
    return refuse("Choose one of the listed reasons.") unless reason_valid?

    # Under the row lock, so a double submit schedules once and mails once: the
    # second request finds the first one's date and does nothing.
    cancellation = current_company.with_lock { schedule! unless current_company.billing_cancellation_scheduled? }
    notify_admins(cancellation) if cancellation

    redirect_to company_settings_billing_path,
                notice: "Your subscription ends on #{ends_on}. Until then everything keeps working."
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

  def schedule!
    subscription = Billing::SubscriptionState.from(
      client.schedule_cancellation(subscription_id: current_company.stripe_subscription_id,
                                   reason: reason, comment: comment)
    )
    cancels_at = subscription.cancels_at || subscription.period_ends_at || current_company.billing_period_ends_at

    current_company.update!(billing_cancels_at: cancels_at)
    current_company.billing_cancellations.create!(user: current_user, reason: reason, comment: comment,
                                                  cancels_at: cancels_at)
  end

  # Every admin, the one who cancelled included: there is no billing contact,
  # and a workspace that stops without the others hearing of it is a support
  # ticket the day it does.
  def notify_admins(cancellation)
    current_company.billing_admins.find_each do |admin|
      BillingMailer.cancellation_scheduled(cancellation, admin).deliver_later
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

  def ends_on
    current_company.billing_cancels_at&.strftime("%B %-d, %Y") || "the end of the billing period"
  end

  def client
    @client ||= Billing::StripeClient.new
  end

  def refuse(message)
    redirect_to company_settings_billing_path, alert: message
  end
end
