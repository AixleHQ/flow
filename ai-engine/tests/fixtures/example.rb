# frozen_string_literal: true

# Service for managing user subscriptions and billing in a SaaS application
class SubscriptionService
  include Serviceable

  attr_reader :stripe_service, :notification_service

  def initialize(stripe_service: StripeService.new, notification_service: NotificationService.new)
    @stripe_service = stripe_service
    @notification_service = notification_service
  end

  # Creates a new subscription for a user with plan validation
  def create_subscription(user, plan_id, payment_method_id = nil)
    return error_result('User already has active subscription') if user.subscription&.active?

    plan = SubscriptionPlan.find_by(id: plan_id)
    return error_result('Invalid subscription plan') unless plan&.available?

    subscription = nil

    ActiveRecord::Base.transaction do
      subscription = user.create_subscription!(
        plan: plan,
        status: 'pending',
        started_at: Time.current,
        next_billing_date: calculate_next_billing_date(plan)
      )

      if plan.paid?
        stripe_subscription = create_stripe_subscription(user, plan, payment_method_id)

        if stripe_subscription[:success]
          subscription.update!(
            status: 'active',
            external_id: stripe_subscription[:subscription_id]
          )

          create_subscription_usage_record(subscription)
          grant_plan_features(user, plan)

          notification_service.send_subscription_confirmation(user, subscription)
        else
          raise ActiveRecord::Rollback, stripe_subscription[:error]
        end
      else
        # Free plan
        subscription.update!(status: 'active')
        grant_plan_features(user, plan)
      end
    end

    success_result(subscription)
  rescue StandardError => e
    Rails.logger.error "Subscription creation failed: #{e.message}"
    error_result("Failed to create subscription: #{e.message}")
  end

  # Cancels a subscription with optional immediate or end-of-period cancellation
  def cancel_subscription(subscription, immediate: false)
    return error_result('Subscription not found') unless subscription
    return error_result('Subscription already cancelled') if subscription.cancelled?

    ActiveRecord::Base.transaction do
      if subscription.external_id.present?
        cancellation_result = stripe_service.cancel_subscription(
          subscription.external_id,
          at_period_end: !immediate
        )

        return error_result(cancellation_result[:error]) unless cancellation_result[:success]
      end

      cancellation_date = immediate ? Time.current : subscription.next_billing_date

      subscription.update!(
        status: 'cancelled',
        cancelled_at: cancellation_date,
        cancellation_reason: 'user_requested'
      )

      revoke_plan_features(subscription.user, subscription.plan) if immediate

      notification_service.send_cancellation_confirmation(subscription.user, subscription)
    end

    success_result(subscription)
  rescue StandardError => e
    Rails.logger.error "Subscription cancellation failed: #{e.message}"
    error_result("Failed to cancel subscription: #{e.message}")
  end

  # Processes subscription renewal and handles payment
  def process_renewal(subscription)
    return error_result('Subscription not eligible for renewal') unless subscription.renewable?

    if subscription.plan.paid?
      payment_result = stripe_service.process_subscription_payment(subscription.external_id)

      unless payment_result[:success]
        handle_payment_failure(subscription, payment_result[:error])
        return error_result("Payment failed: #{payment_result[:error]}")
      end
    end

    subscription.update!(
      next_billing_date: calculate_next_billing_date(subscription.plan),
      last_billed_at: Time.current
    )

    create_subscription_usage_record(subscription)
    notification_service.send_renewal_confirmation(subscription.user, subscription)

    success_result(subscription)
  end

  private

  def create_stripe_subscription(user, plan, payment_method_id)
    stripe_service.create_subscription(
      customer_id: user.stripe_customer_id,
      price_id: plan.stripe_price_id,
      payment_method_id: payment_method_id
    )
  end

  def calculate_next_billing_date(plan)
    case plan.billing_interval
    when 'monthly'
      1.month.from_now
    when 'yearly'
      1.year.from_now
    when 'weekly'
      1.week.from_now
    else
      raise ArgumentError, "Unsupported billing interval: #{plan.billing_interval}"
    end
  end

  def grant_plan_features(user, plan)
    plan.features.each do |feature|
      user.feature_access.find_or_create_by(feature: feature) do |access|
        access.granted_at = Time.current
      end
    end
  end

  def revoke_plan_features(user, plan)
    plan.features.each do |feature|
      user.feature_access.find_by(feature: feature)&.destroy
    end
  end

  def create_subscription_usage_record(subscription)
    SubscriptionUsage.create!(
      subscription: subscription,
      period_start: subscription.last_billed_at || subscription.started_at,
      period_end: subscription.next_billing_date,
      usage_data: {}
    )
  end

  def handle_payment_failure(subscription, error_message)
    subscription.update!(
      status: 'past_due',
      last_payment_error: error_message
    )

    notification_service.send_payment_failure_notification(subscription.user, subscription)
  end
end
