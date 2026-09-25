# frozen_string_literal: true

# What the remove-member and leave-company dialogs need to hand a member's
# projects over before the membership is revoked.
class ProjectHandover
  def self.for_company(company, owner: nil)
    projects = company.projects.order(:name)
    projects = projects.where(owner_id: owner.id) if owner

    {
      projects: projects.pluck(:id, :name, :owner_id).map { |id, name, owner_id| { id: id, name: name, owner_id: owner_id } },
      candidates: candidate_rows(company.ownership_candidates),
      # CompanyMembership.heir_for's order: the dialog preselects the first of
      # these who is not the member leaving.
      heir_ids: company.company_memberships.active.where(role: "admin").default_order.pluck(:user_id)
    }
  end

  def self.candidate_rows(users)
    users.order(:name).pluck(:id, :name, :email, "company_memberships.role").map do |id, name, email, role|
      { id: id, name: name, email: email, company_admin: role == "admin" }
    end
  end
end
