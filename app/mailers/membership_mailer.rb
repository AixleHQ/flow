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
end
