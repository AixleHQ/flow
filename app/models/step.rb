# frozen_string_literal: true

class Step < ApplicationRecord
  extend Enumerize
  include ProjectOwnedReferences

  SUPPORTED_AGENT_RUNTIMES = %w[claude_code cursor_cli codex gemini_cli antigravity_cli].freeze

  belongs_to :workflow
  belongs_to :agent, optional: true

  has_many :step_runs, dependent: :destroy
  has_many :sub_steps, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :sub_steps, allow_destroy: true

  enumerize :skip_policy, in: %i[never if_outputs_exist manual], default: :never
  enumerize :on_failure, in: %i[retry skip fail], default: :fail

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :workflow_id }
  validates :preferred_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true
  validates :required_agent_runtime, inclusion: { in: SUPPORTED_AGENT_RUNTIMES }, allow_nil: true
  validate :depends_on_step_ids_valid
  validate :config_item_ids_belong_to_project
  validate :resource_ids_belong_to_project

  default_scope { order(:position) }

  scope :not_deleted, -> { where(deleted_at: nil) }

  before_validation :assign_next_position, on: :create

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Always a soft delete: a version snapshot names steps by id, and a revert
  # brings one back by clearing `deleted_at` — a hard-deleted id would leave the
  # snapshot's `depends_on_step_ids` pointing at nothing.
  def destroy
    dependent = workflow.steps.not_deleted.where.not(id: id)
                        .where("depends_on_step_ids @> ?::jsonb", [ id ].to_json)
    if dependent.any?
      errors.add(:base, "Cannot delete step: #{dependent.pluck(:name).join(', ')} depend on it")
      return false
    end

    soft_delete!
    self
  end

  def dependency_steps
    return Step.none if depends_on_step_ids.blank?

    workflow.steps.not_deleted.where(id: depends_on_step_ids)
  end

  def root?
    depends_on_step_ids.blank?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name position created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[workflow agent sub_steps]
  end

  private

  # Appending is the server's job. A soft-deleted step keeps its position and
  # the unique (workflow_id, position) index still covers it, so the next free
  # slot has to be read from every row — a client that counts only the steps it
  # can see lands on a deleted one's number and the insert fails.
  def assign_next_position
    return if position.present?

    self.position = workflow&.steps&.maximum(:position).to_i + 1
  end

  # A step may only name config items of its workflow's own project — the ids
  # decide what `get_config_item` will decrypt for the step's session, so they
  # are never taken on trust from the request that set them.
  def config_item_ids_belong_to_project
    return if config_item_ids.blank?

    unless workflow&.scope_type == "Project"
      errors.add(:config_item_ids, "can only be set on a project-scoped workflow")
      return
    end

    owned = ConfigItem.where(scope_type: "Project", scope_id: workflow.scope_id, id: config_item_ids).pluck(:id)
    foreign = config_item_ids.map(&:to_i) - owned
    return if foreign.empty?

    errors.add(:config_item_ids, "contains items outside this project: #{foreign.sort.join(', ')}")
  end

  STEP_RESOURCES = {
    agent_id: :agents, tool_ids: :tools, skill_ids: :skills, mcp_server_ids: :mcp_servers,
    asset_ids: :assets, repository_ids: :repositories
  }.freeze

  def resource_ids_belong_to_project
    return unless workflow&.scope_type == "Project"

    STEP_RESOURCES.each do |attribute, kind|
      next unless will_save_change_to_attribute?(attribute)

      validate_owned_ids(workflow.scope, kind, attribute, attribute_in_database(attribute), self[attribute])
    end
  end

  def depends_on_step_ids_valid
    return if depends_on_step_ids.blank?

    if depends_on_step_ids.include?(id)
      errors.add(:depends_on_step_ids, "cannot include self")
      return
    end

    siblings = workflow.steps.not_deleted.where.not(id: id).pluck(:id, :name, :depends_on_step_ids)
    invalid_ids = depends_on_step_ids - siblings.map(&:first)
    if invalid_ids.any?
      errors.add(:depends_on_step_ids, "contains invalid step ids: #{invalid_ids.join(', ')}")
      return
    end

    cycle = dependency_cycle(siblings)
    errors.add(:depends_on_step_ids, "would create a cycle: #{cycle.join(' → ')}") if cycle
  end

  # A run starts only the steps whose dependencies have all finished, so steps
  # that wait on each other never start, and the run ends with them still pending.
  def dependency_cycle(siblings)
    return nil if new_record?

    names = siblings.to_h { |step_id, step_name, _| [ step_id, step_name ] }.merge(id => name)
    graph = siblings.to_h { |step_id, _, deps| [ step_id, Array(deps) ] }.merge(id => depends_on_step_ids)
    path = path_back_to_self(graph)
    path&.map { |step_id| names[step_id] }
  end

  def path_back_to_self(graph)
    stack = [ [ id, [ id ] ] ]
    seen = Set.new
    until stack.empty?
      step_id, path = stack.pop
      graph.fetch(step_id, []).each do |dep|
        return path + [ id ] if dep == id
        next unless seen.add?(dep)

        stack.push([ dep, path + [ dep ] ])
      end
    end
    nil
  end
end
