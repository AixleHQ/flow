# frozen_string_literal: true

class MembershipMailer < ApplicationMailer
  # Invitation email with a signed accept link. The token embeds the membership
  # state, so any transition (accept/revoke) invalidates outstanding links;
  # tokens also expire after 7 days (see CompanyMembership#generates_token_for).
  def invitation(membership)
    @membership = membership
    @company = membership.company
    @inviter = membership.invited_by
    @role = membership.role.to_s
    @accept_url = invitation_url(membership.generate_token_for(:invitation))

    mail(
      to: membership.user.email,
      subject: "You've been invited to #{@company.branded_name} on Aixle Flow"
    )
  end

  # Reminder for an invitation that is still unaccepted and close to expiring.
  # Regenerates the link from the CURRENT token payload, so the reminder always
  # carries a working link even though the original mail's link is the same one
  # (invited_at is untouched — touching it would reset the 7-day clock).
  def invitation_reminder(membership)
    @membership = membership
    @company = membership.company
    @inviter = membership.invited_by
    @role = membership.role.to_s
    @accept_url = invitation_url(membership.generate_token_for(:invitation))
    @expires_at = membership.invited_at + CompanyMembership::INVITATION_VALID_FOR

    mail(
      to: membership.user.email,
      subject: "Your invitation to #{@company.branded_name} expires soon"
    )
  end

  # To the person who sent the invitation, once it is accepted.
  def invitation_accepted(membership)
    @membership = membership
    @company = membership.company
    @member = membership.user
    @role = membership.role.to_s

    mail(
      to: membership.invited_by.email,
      subject: "#{@member.name} joined #{@company.branded_name}"
    )
  end

  # To the member, when their access to a company is withdrawn.
  def access_revoked(membership)
    @company = membership.company
    @member = membership.user

    mail(
      to: @member.email,
      subject: "Your access to #{@company.branded_name} has been removed"
    )
  end

  # To the member, when their role in a company changes. `previous_role` comes
  # from the caller because the record has already been saved by then.
  def role_changed(membership, previous_role)
    @company = membership.company
    @member = membership.user
    @role = membership.role.to_s
    @previous_role = previous_role.to_s

    mail(
      to: @member.email,
      subject: "Your role in #{@company.branded_name} is now #{@role.humanize}"
    )
  end
end
