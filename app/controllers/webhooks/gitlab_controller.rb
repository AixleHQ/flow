# frozen_string_literal: true

class Webhooks::GitlabController < ActionController::API
  before_action :authenticate_by_repository

  def receive
    event = request.headers["X-Gitlab-Event"]

    case event
    when "Pipeline Hook"
      handle_pipeline
    end

    head :ok
  end

  private

  def handle_pipeline
    payload = request.request_parameters
    status = payload.dig("object_attributes", "status")
    return unless status.in?(%w[success failed canceled])

    pipeline_id = payload.dig("object_attributes", "id")
    mr_iid = payload.dig("merge_request", "iid")

    ResolveGitlabPipelineJob.perform_later(
      repository_id: @repository.id,
      pipeline_id: pipeline_id,
      status: status,
      mr_iid: mr_iid
    )
  end

  # Several repositories can name the same GitLab project — two companies, or two
  # projects of one — each with its own hook and secret. The delivery belongs to
  # the one whose secret it carries, and resolves that repository's gates only.
  def authenticate_by_repository
    payload = request.request_parameters
    path_with_namespace = payload.dig("project", "path_with_namespace")
    token_header = request.headers["X-Gitlab-Token"]
    return head :unauthorized if path_with_namespace.blank? || token_header.blank?

    @repository = Repository.where(full_name: path_with_namespace).where.not(webhook_secret: [ nil, "" ]).find do |repository|
      ActiveSupport::SecurityUtils.secure_compare(token_header, repository.webhook_secret)
    end
    head :unauthorized unless @repository
  end
end
