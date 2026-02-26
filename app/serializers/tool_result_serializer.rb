# frozen_string_literal: true

class ToolResultSerializer < ApplicationSerializer
  URL_TTL = 3600

  attributes :execution_id, :state, :exit_code, :error, :duration_ms, :created_at,
             :tool_name,
             :stdout_url, :stdout_size,
             :stderr_url, :stderr_size,
             :result_data_url, :result_data_size,
             :output_url, :output_size

  def tool_name       = object.tool.name

  def stdout_url      = rewrite_host(object.stdout&.url(expires_in: URL_TTL))
  def stdout_size     = object.stdout&.metadata&.dig("size")

  def stderr_url      = rewrite_host(object.stderr&.url(expires_in: URL_TTL))
  def stderr_size     = object.stderr&.metadata&.dig("size")

  def result_data_url  = rewrite_host(object.result_data&.url(expires_in: URL_TTL))
  def result_data_size = object.result_data&.metadata&.dig("size")

  def output_url      = rewrite_host(object.output&.url(expires_in: URL_TTL))
  def output_size     = object.output&.metadata&.dig("size")

  private

  # Pass `url_host: "http://web:4000"` to rewrite presigned URLs for container access.
  def rewrite_host(url)
    return url if url.blank?

    host = @instance_options[:url_host]
    return url if host.blank?

    override = URI.parse(host.start_with?("http") ? host : "http://#{host}")
    uri = URI.parse(url)
    uri.scheme = override.scheme
    uri.host = override.host
    uri.port = override.port
    uri.to_s
  rescue URI::InvalidURIError
    url
  end
end
