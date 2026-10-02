# frozen_string_literal: true

class ToolResultResource
  include Alba::Resource

  URL_TTL = 3600

  transform_keys :none

  attributes :execution_id, :state, :exit_code, :error, :duration_ms, :created_at

  attribute :tool_name do |tr|
    tr.tool.name
  end

  attribute(:stdout_url) { |tr| rewrite_host(tr.stdout&.url(expires_in: URL_TTL)) }
  attribute(:stdout_size) { |tr| tr.stdout&.metadata&.dig("size") }
  attribute(:stderr_url) { |tr| rewrite_host(tr.stderr&.url(expires_in: URL_TTL)) }
  attribute(:stderr_size) { |tr| tr.stderr&.metadata&.dig("size") }
  attribute(:result_data_url) { |tr| rewrite_host(tr.result_data&.url(expires_in: URL_TTL)) }
  attribute(:result_data_size) { |tr| tr.result_data&.metadata&.dig("size") }
  attribute(:output_url) { |tr| rewrite_host(tr.output&.url(expires_in: URL_TTL)) }
  attribute(:output_size) { |tr| tr.output&.metadata&.dig("size") }

  private

  def rewrite_host(url)
    ContainerAssetUrl.call(url, host: params[:url_host])
  end
end
