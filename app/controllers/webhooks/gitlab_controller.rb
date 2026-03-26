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
      repo_full_name: @repository.full_name,
      pipeline_id: pipeline_id,
      status: status,
      mr_iid: mr_iid
    )
  end

  def authenticate_by_repository
    payload = request.request_parameters
    path_with_namespace = payload.dig("project", "path_with_namespace")
    return head :unauthorized if path_with_namespace.blank?

    @repository = Repository.find_by(full_name: path_with_namespace)
    return head :unauthorized unless @repository

    token_header = request.headers["X-Gitlab-Token"]
    return head :unauthorized if token_header.blank?
    return head :unauthorized if @repository.webhook_secret.blank?

    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(
      token_header,
      @repository.webhook_secret
    )
  end
end
