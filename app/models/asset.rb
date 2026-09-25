# frozen_string_literal: true

class Asset < ApplicationRecord
  # `folder` holds the same path shape as `Folder#path` — see `Folder::PATH_FORMAT` for what a
  # segment may contain, and `Folder` for why paths (not a `parent_id`) are the source of truth
  # for nesting.
  FOLDER_MAX_LENGTH = 100
  UNSHARED = PubliclyShareable::UNSHARED.merge(public: false).freeze

  belongs_to :scope, polymorphic: true
  include TenantColumns
  include PubliclyShareable
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :step_run, optional: true
  belongs_to :terminal_session, optional: true

  has_many :versions, class_name: "AssetVersion", dependent: :destroy, inverse_of: :asset

  before_validation :normalize_folder

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id folder], message: "already exists in this scope",
                                 conditions: -> { where(deleted_at: nil) } }
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[active pending_review dismissed] }
  validates :folder, length: { maximum: FOLDER_MAX_LENGTH }, allow_blank: true
  validate :folder_shape

  scope :active, -> { where(deleted_at: nil, status: "active") }
  # A deleted asset's link is dead even if something left its token behind.
  scope :publicly_shared, -> { where(public: true, deleted_at: nil).where.not(public_token: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :pending_review, -> { where(status: "pending_review") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :for_company, ->(company) { active.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { active.where(scope_type: "Project", scope_id: project.id) }
  scope :accessible_from_project, ->(project) {
    active
      .where(scope_type: "Project", scope_id: project.id)
      .or(active.where(scope_type: "Company", scope_id: project.company_id))
  }
  scope :downloadable_from_project, ->(project) {
    where(deleted_at: nil)
      .where(status: %w[active pending_review])
      .where(scope_type: "Project", scope_id: project.id)
      .or(
        where(deleted_at: nil)
          .where(status: %w[active pending_review])
          .where(scope_type: "Company", scope_id: project.company_id)
      )
  }
  scope :scoped_to_project, ->(project) {
    where(scope_type: "Project", scope_id: project.id)
      .or(where(scope_type: "Company", scope_id: project.company_id))
  }

  scope :visible_for_project, ->(project) {
    active.where(scope_type: "Project", scope_id: project.id)
          .or(active.where(scope_type: "Company", scope_id: project.company_id))
  }
  scope :visible_for_company, ->(company) { for_company(company) }

  # Canonical form of a folder, with blank meaning "root" (nil). Every write and every lookup has
  # to agree on it — `find_by(folder: " docs ")` would otherwise miss the row stored as "docs"
  # and silently create a duplicate asset. `Folder` owns the rule, since the two must not drift.
  def self.normalize_folder(value)
    Folder.normalize_path(value)
  end

  # The folder rules as a predicate, for callers that reject a bad argument before building the
  # record (agent tools, which owe their caller a message rather than a RecordInvalid).
  def self.invalid_folder?(value)
    folder = normalize_folder(value)
    return false if folder.nil?

    Folder.invalid_path?(folder) || folder.length > FOLDER_MAX_LENGTH
  end

  def picker_name
    folder.present? ? "#{folder}/#{name}" : name
  end

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  def latest_version
    versions.order(version: :desc).first
  end

  def resolve_version(version_number = nil)
    if version_number.present?
      versions.find_by!(version: version_number)
    else
      latest_version or raise ActiveRecord::RecordNotFound, "No versions for asset"
    end
  end

  def shared?
    public? && public_token.present?
  end

  # The token lives on the asset, not on a version, so a shared link keeps
  # serving whichever version is newest.
  def shared_file = latest_version&.file
  def shared_content_type = latest_version&.content_type

  def soft_delete!
    update!(UNSHARED.merge(deleted_at: Time.current))
  end

  def restore!
    raise ActiveRecord::RecordNotFound, "Asset is not deleted" unless deleted?

    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name folder scope_type status terminal_session_id deleted_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope created_by terminal_session versions]
  end

  private

  def share_attributes = { public: true }
  def unshare_attributes = UNSHARED

  def normalize_folder
    self.folder = self.class.normalize_folder(folder)
  end

  # A blank folder means "root", so only a present one has a shape to check.
  def folder_shape
    return if folder.blank?

    errors.add(:folder, Folder::PATH_MESSAGE) if Folder.invalid_path?(folder)
  end
end
