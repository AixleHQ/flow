# frozen_string_literal: true

require "administrate/base_dashboard"

class WorkflowRunAssetDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :workflow_run

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    workflow_run: Field::BelongsTo,
    produced_by_step_run: Field::BelongsTo.with_options(optional: true),
    name: Field::String,
    content_type: Field::String,
    file_size: Field::Number,
    file: Field::Shrine.with_options(url_only: true),
    s3_key: Field::String,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    workflow_run
    name
    content_type
    file_size
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    workflow_run
    produced_by_step_run
    name
    content_type
    file_size
    file
    s3_key
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(asset)
    "#{asset.name} (##{asset.id})"
  end
end
