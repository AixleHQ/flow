# frozen_string_literal: true

# Invites one address into a company. The Members screen invites through it, and
# so does the admin panel when it sets a tenant up, so a person invited by an
# operator gets exactly what a company admin would have sent them.
#
# Without an inviter the invitation is from "An administrator": the admin panel
# invites that way, so an operator's name and address never reach a customer.
#
# A new address becomes a passwordless User: credentials come with the
# invitation signup. A pending invitation is sent again, and a revoked
# membership is invited again in its own row, since a user holds one membership
# per company. Anyone already in the company is left alone.
class CompanyInvitation
  Result = Data.define(:status, :email, :errors) do
    def sent? = status.in?(%i[invited resent])

    def message
      case status
      when :invited then "Invitation sent to #{email}"
      when :resent then "Invitation re-sent to #{email}"
      when :platform_admin then "#{email} is a platform administrator and cannot be invited"
      when :already_member then "#{email} is already a member of this company"
      when :already_invited then "#{email} has already been invited"
      when :invalid then "#{email}: #{errors.full_messages.to_sentence}"
      end
    end
  end

  def self.call(...) = new(...).call

  # A pasted list — commas, semicolons, spaces or new lines between addresses —
  # invited with one role, each address once.
  def self.invite_all(company:, addresses:, inviter: nil, role: nil)
    addresses.to_s.downcase.split(/[\s,;]+/).compact_blank.uniq.map do |email|
      call(company:, inviter:, email:, role:)
    end
  end

  def initialize(company:, email:, inviter: nil, name: nil, role: nil)
    @company = company
    @inviter = inviter
    @email = email.to_s.strip.downcase
    @name = name.presence
    @role = role.presence || "employee"
  end

  def call
    user = User.find_or_initialize_by(email: @email)
    # Super admins hold no memberships.
    return result(:platform_admin) if user.persisted? && user.super_admin?

    membership = @company.company_memberships.find_by(user_id: user.id) if user.persisted?

    if membership.nil? then invite(user)
    elsif membership.invited? then resend(membership)
    elsif membership.revoked? then reinvite(membership)
    else result(:already_member)
    end
  rescue ActiveRecord::RecordNotUnique
    # The same address invited twice at once: the user or the membership index.
    result(:already_invited)
  end

  private

  def invite(user)
    user.name = @name || name_from_email if user.name.blank?
    membership = user.company_memberships.build(
      company: @company, role: @role, invited_by: @inviter, invited_at: Time.current
    )
    return result(:invalid, user.errors.presence || membership.errors) unless user.save

    deliver(membership, :invited)
  end

  # Touching invited_at rotates the token, so the link mailed before stops working.
  def resend(membership)
    membership.update!(invited_at: Time.current)
    deliver(membership, :resent)
  end

  def reinvite(membership)
    membership.assign_attributes(role: @role, invited_by: @inviter, invited_at: Time.current, accepted_at: nil)
    membership.aasm(:state).fire(:reinvite)
    return result(:invalid, membership.errors) unless membership.save

    deliver(membership, :invited)
  end

  def deliver(membership, status)
    MembershipMailer.invitation(membership).deliver_later
    result(status)
  end

  # Only a placeholder: the invitation signup asks the person for their name.
  def name_from_email
    @email.split("@").first.to_s.tr("._-", " ").titleize
  end

  def result(status, errors = nil) = Result.new(status:, email: @email, errors:)
end
