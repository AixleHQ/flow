# frozen_string_literal: true

# Previews at /rails/mailers/membership_mailer — the only way to eyeball the
# table-based email markup against the branded layout without sending anything.
# Uses whatever data is already in the database rather than creating records.
class MembershipMailerPreview < ActionMailer::Preview
  def invitation
    MembershipMailer.invitation(sample_membership)
  end

  def invitation_reminder
    MembershipMailer.invitation_reminder(sample_membership(invited_at: 6.days.ago))
  end

  def invitation_accepted
    MembershipMailer.invitation_accepted(sample_membership)
  end

  def access_revoked
    MembershipMailer.access_revoked(sample_membership)
  end

  def role_changed
    MembershipMailer.role_changed(sample_membership, "employee")
  end

  private

  # A persisted membership when one exists (generate_token_for needs an id),
  # otherwise an unsaved stand-in built from the first user/company available.
  def sample_membership(invited_at: 1.day.ago)
    membership = CompanyMembership.where.not(invited_by_id: nil).last || CompanyMembership.last
    return membership.tap { |m| m.invited_at ||= invited_at } if membership

    CompanyMembership.new(
      id: 0,
      user: User.first || User.new(name: "Jane Doe", email: "jane@example.com"),
      company: Company.first || Company.new(name: "Globex Labs"),
      invited_by: User.first,
      role: "employee",
      state: "invited",
      invited_at: invited_at
    )
  end
end
