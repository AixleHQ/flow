# frozen_string_literal: true

class ProjectMemory < ApplicationRecord
  belongs_to :project
  belongs_to :terminal_session, optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  has_many :memory_retrievals, dependent: :destroy

  attr_readonly :revision, :project_id, :title, :content, :topic_key, :terminal_session_id, :base_revision, :language, :tags
  before_validation :assign_revision, on: :create
  before_destroy :remember_cleanup_namespace
  after_destroy_commit :cleanup_destroyed_projection
  after_update_commit :cleanup_projection, if: -> { saved_change_to_state? && state != "validated" }
  validates :title, presence: true, length: { maximum: 120 }
  validates :content, presence: true, length: { maximum: 2000 }
  validates :topic_key, presence: true, length: { maximum: 100 }
  validates :language, inclusion: { in: Project::ARTIFACTS_LANGUAGES }
  validates :state, inclusion: { in: %w[pending validated obsolete] }
  validates :revision, presence: true, uniqueness: true

  scope :reusable, -> { where(state: "validated").where("review_at > ?", Time.current).where.not(engram_id: nil) }

  private

  def remember_cleanup_namespace
    @cleanup_namespace = "flow:company:#{project.company_id}:project:#{project_id}"
  end

  def cleanup_destroyed_projection
    EngramCleanupJob.perform_later(engram_id, @cleanup_namespace) if engram_id.present?
  end

  def cleanup_projection
    return if engram_id.blank?

    owner = project
    EngramCleanupJob.perform_later(engram_id, "flow:company:#{owner.company_id}:project:#{project_id}")
  end

  def assign_revision
    self.revision ||= SecureRandom.uuid
  end
end
