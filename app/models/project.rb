# frozen_string_literal: true

class Project < ApplicationRecord
  extend Enumerize

  # Constants
  ARTIFACTS_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze

  enumerize :state, in: %i[active paused archived], default: :active, predicates: true, scope: true

  # Associations
  belongs_to :company
  belongs_to :owner, class_name: "User", inverse_of: :owned_projects
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborators, through: :project_collaborators, source: :user
  has_many :project_favorites, dependent: :destroy
  has_many :favorited_by_users, through: :project_favorites, source: :user
  has_many :terminal_sessions, dependent: :nullify
  has_many :config_items, as: :scope, dependent: :destroy
  has_many :agents, as: :scope, dependent: :destroy
  has_many :tools, as: :scope, dependent: :destroy
  has_many :mcp_servers, as: :scope, dependent: :destroy, class_name: "MCPServer"
  has_many :skills, as: :scope, dependent: :destroy
  has_many :assets, as: :scope, dependent: :destroy
  has_many :repositories, as: :scope, dependent: :destroy
  has_many :workflows, as: :scope, dependent: :destroy
  has_many :workflow_runs, dependent: :destroy
  has_one :board, dependent: :destroy
  has_one :namespace_resource_quota, as: :scope, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :slug, presence: true,
                   uniqueness: { scope: :company_id },
                   format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :preferred_artifacts_language, inclusion: { in: ARTIFACTS_LANGUAGES }, allow_nil: false
  validate :owner_belongs_to_company

  # Callbacks
  before_validation :generate_slug, on: :create

  # Scopes
  scope :with_computed_counts, -> {
    select(
      "projects.*",
      "(SELECT COUNT(*) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_sessions_count",
      "(SELECT MAX(terminal_sessions.started_at) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_last_activity_at",
      "(SELECT COUNT(*) FROM workflows WHERE workflows.scope_id = projects.id AND workflows.scope_type = 'Project' AND workflows.deleted_at IS NULL) AS cached_workflows_count",
      "(SELECT COUNT(*) FROM board_tasks INNER JOIN boards ON boards.id = board_tasks.board_id WHERE boards.project_id = projects.id) AS cached_board_tasks_count",
      "(SELECT COUNT(*) FROM project_collaborators WHERE project_collaborators.project_id = projects.id) AS cached_collaborators_count"
    )
  }
  scope :for_company, ->(company) { where(company: company) }
  # Favorites-first ordering for ONE user, as an ORDER BY prefix: chain the
  # list's own ordering after it (`favorites_first_for(user).order(:name)`) so
  # the existing order still decides everything within each group.
  #
  # A subquery rather than a join: joining project_favorites would either drop
  # the non-favorites (INNER) or need a user-filtered LEFT JOIN condition, and
  # both fight with the `select` that with_computed_counts already builds.
  scope :favorites_first_for, ->(user) {
    favorite_project_ids = ProjectFavorite.where(user_id: user&.id).select(:project_id)

    order(Arel.sql("CASE WHEN projects.id IN (#{favorite_project_ids.to_sql}) THEN 0 ELSE 1 END"))
  }
  scope :for_user, ->(user) {
    member_company_ids = user.company_memberships.active.select(:company_id)
    admin_company_ids = user.company_memberships.active.where(role: "admin").select(:company_id)

    # Owner/collaborator access requires an ACTIVE membership in the project's
    # company — a user revoked from a company loses its projects even if they
    # still own rows there. (Super admins don't use this scope — /admin only.)
    where(company_id: admin_company_ids)
      .or(where(owner: user).where(company_id: member_company_ids))
      .or(where(id: user.collaborated_projects.select(:id)).where(company_id: member_company_ids))
  }

  # Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[name description state created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[company owner]
  end

  # Add a user as collaborator (idempotent)
  def add_collaborator(user)
    project_collaborators.find_or_create_by!(user: user)
  end

  # Remove a user from project
  def remove_collaborator(user)
    project_collaborators.find_by(user: user)&.destroy
  end

  # Check if user has access to project (owner, collaborator, or company admin).
  # ALL branches require an active membership in the project's company: being
  # revoked from the company removes access even for owners/collaborators.
  # Deliberately a LIVE query, not User#active_memberships: that list is
  # memoized per User instance, so a revocation followed by an access check on
  # the same object would answer from the stale list and still grant access.
  # This is a security predicate — it must see the current state.
  # One find_by (not the two exists? calls it replaces) covers both the
  # membership requirement and the company-admin branch.
  def accessible_by?(user)
    return false unless user

    membership = user.company_memberships.active.find_by(company_id: company_id)
    return false unless membership

    owner_id == user.id ||
      membership.admin? ||
      project_collaborators.exists?(user: user)
  end

  # Check if user is admin of project (owner only)
  def admin?(user)
    owner_id == user.id
  end

  # Returns all member users (owner first, then collaborators)
  def member_users
    collaborator_ids = project_collaborators.pluck(:user_id)
    User.where(id: [ owner_id ] + collaborator_ids)
        .order(Arel.sql("CASE WHEN id = #{owner_id} THEN 0 ELSE 1 END"))
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    # Ensure uniqueness within company
    counter = 1
    while company && Project.exists?(company: company, slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def owner_belongs_to_company
    return unless owner && company
    return if owner.company_memberships.active.exists?(company_id: company_id)

    errors.add(:owner, "must have an active membership in the project's company")
  end
end
