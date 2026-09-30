# frozen_string_literal: true

# One external project (an Azure DevOps project, a Jira project, …) of a
# connection, mapped into one Aixle project. The connection holds the
# credentials; this row is what agents and triggers address, by `handle`.
# See docs/design/task-tracker-integrations.md §4.
class ProjectTracker < ApplicationRecord
  extend Enumerize

  HANDLE_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\z/

  enumerize :access, in: %i[read_write read_only], default: :read_write, predicates: true
  enumerize :status, in: %i[active error detached], default: :active, predicates: true, scope: true

  belongs_to :project
  belongs_to :integration
  has_many :tracker_operations, dependent: :delete_all
  has_many :trigger_bindings, dependent: :nullify
  # Only a hard delete (its connection removed) gets here; a person detaches. The
  # triggers stop first, so none is left enabled and widened to "any tracker".
  before_destroy(prepend: true) { trigger_bindings.update_all(enabled: false) }

  validates :name, :external_scope_id, presence: true
  validates :handle, presence: true, format: { with: HANDLE_FORMAT, message: "must be lowercase letters, digits and dashes" },
                     uniqueness: { scope: :project_id }
  validates :external_scope_id, uniqueness: { scope: %i[project_id integration_id] }
  validates :provider, inclusion: { in: ->(_) { Trackers::PROVIDERS.keys } }
  validate :integration_serves_project, if: -> { integration && project }
  validate :scope_covered_by_integration, if: -> { integration && external_scope_id.present? && !detached? }

  before_validation :copy_provider, if: -> { integration && provider.blank? }
  before_validation :normalize_handle

  scope :for_project, ->(project) { where(project_id: project.id) }
  scope :usable, -> { where(status: "active").joins(:integration).merge(Integration.active) }

  def self.handle_for(name, taken: [])
    base = name.to_s.parameterize.first(60).delete_suffix("-").presence || "tracker"
    candidate = base
    suffix = 1
    candidate = "#{base}-#{suffix += 1}" while taken.include?(candidate)
    candidate
  end

  def tracker_provider
    Trackers::Provider.for(integration)
  end

  def usable?
    active? && integration&.active?
  end

  def writable?
    usable? && read_write?
  end

  def make_primary!
    transaction do
      ProjectTracker.for_project(project).where.not(id: id).where(primary: true).update_all(primary: false)
      update!(primary: true)
    end
  end

  # Detached rather than deleted: provisioning would otherwise bring back a
  # tracker someone removed on purpose, and what referenced it keeps a target.
  def detach!
    update!(status: :detached, primary: false)
  end

  def reattach!
    update!(status: :active)
  end

  private

  def copy_provider
    self.provider = integration.provider.to_s
  end

  def normalize_handle
    self.handle = handle.to_s.strip.downcase.presence if handle
  end

  def integration_serves_project
    return if Trackers::Provider.for(integration).serves_project?(project)

    errors.add(:integration, "is not available to this project")
  end

  def scope_covered_by_integration
    return if Trackers::Provider.for(integration).covers_scope?(external_scope_id)

    errors.add(:external_scope_id, "is not covered by this connection")
  end
end
