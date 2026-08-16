# frozen_string_literal: true

class BoardTask < ApplicationRecord
  extend Enumerize

  belongs_to :board
  belongs_to :board_column
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :parent_task, class_name: "BoardTask", optional: true
  has_many :child_tasks, class_name: "BoardTask", foreign_key: :parent_task_id, dependent: :nullify
  has_many :task_comments, dependent: :destroy
  has_many :task_assets, dependent: :destroy
  has_many :workflow_runs, dependent: :nullify
  has_many :column_transitions, dependent: :delete_all
  has_many :board_activities, dependent: :delete_all
  has_many :gates, dependent: :destroy
  has_many :pending_gates, -> { pending }, class_name: "Gate", dependent: :destroy

  enumerize :task_type, in: %i[epic story bug not_specified], default: :not_specified, predicates: true
  enumerize :priority, in: %i[low medium high critical]

  validates :title, presence: true
  validate :column_belongs_to_board

  validate :parent_must_be_epic, if: -> { parent_task_id.present? }
  validate :parent_same_board, if: -> { parent_task_id.present? }
  validate :max_one_level_nesting, if: -> { parent_task_id.present? }
  validate :assignee_is_project_member, if: -> { assignee_id.present? }

  before_validation :assign_next_position, on: :create
  after_commit :touch_board
  after_commit :broadcast_task_updates

  # How many tasks one board column loads at a time — the size of the first page
  # the board page ships in its props, and of every page the column then pulls in
  # as it is scrolled.
  PAGE_SIZE = 25

  scope :for_company, ->(company) { joins(board: :project).where(projects: { company_id: company.id }) }
  scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
  scope :tags_overlap, ->(tags) { where("tags && ARRAY[?]::varchar[]", Array(tags)) }
  scope :tags_contains, ->(tags) { where("tags @> ARRAY[?]::varchar[]", Array(tags)) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  # Board ordering. `position` is only unique-ish within a column, so the id keeps
  # offset pagination from re-serving or skipping a row between pages.
  scope :in_board_order, -> { order(:position, :id) }

  # The first `limit` tasks of *every* column, in one query — what keeps the board's
  # initial payload bounded on a board with hundreds of tasks per column. Ranking
  # happens in a window function because SQL has no per-group LIMIT.
  scope :first_per_column, ->(limit) {
    ranked = all.reorder(nil).select(
      "board_tasks.id, ROW_NUMBER() OVER (" \
      "PARTITION BY board_tasks.board_column_id ORDER BY board_tasks.position ASC, board_tasks.id ASC" \
      ") AS column_rank"
    )

    where(id: BoardTask.from(ranked, :ranked).where("ranked.column_rank <= ?", limit).select("ranked.id"))
  }

  def archived?
    archived_at.present?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[title task_type priority assignee_id board_column_id parent_task_id position created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[board board_column assignee parent_task child_tasks]
  end

  private

  def touch_board
    board.touch if board&.persisted?
  end

  def broadcast_task_updates
    broadcast_refresh_to(self)
  end

  def assign_next_position
    return if position.present?

    self.position = board_column&.board_tasks&.maximum(:position).to_i + 1
  end

  def column_belongs_to_board
    return unless board_column && board
    return if board_column.board_id == board_id

    errors.add(:board_column, "must belong to the same board")
  end

  def parent_must_be_epic
    errors.add(:parent_task, "must be an epic") unless parent_task&.task_type&.to_sym == :epic
  end

  def parent_same_board
    errors.add(:parent_task, "must belong to the same board") unless parent_task&.board_id == board_id
  end

  def max_one_level_nesting
    errors.add(:parent_task, "cannot nest more than one level deep") if parent_task&.parent_task_id.present?
  end

  def assignee_is_project_member
    return if assignee && board&.project&.accessible_by?(assignee)

    errors.add(:assignee, "must be a member of the project")
  end
end
