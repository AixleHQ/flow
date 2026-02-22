# frozen_string_literal: true

class WorkflowOutputCollector
  OUTPUTS_DIR = "/workspace/outputs"
  MAX_FILE_SIZE = 500.megabytes

  def initialize(step_run)
    @step_run = step_run
    @workflow_run = step_run.workflow_run
  end

  def collect!
    return [] unless container_available?

    files = list_output_files
    assets = files.filter_map { |path| collect_file(path) }

    Rails.logger.info("[WorkflowOutputCollector] Collected #{assets.size} assets from step_run=#{@step_run.id}")
    assets
  end

  private

  def container_available?
    @step_run.terminal_session&.container_id.present?
  end

  def list_output_files
    container_id = @step_run.terminal_session.container_id
    result = DockerClient.exec(container_id, "find #{OUTPUTS_DIR} -type f 2>/dev/null")
    return [] unless result[:success]

    result[:output].split("\n").map(&:strip).reject(&:blank?)
  rescue StandardError => e
    Rails.logger.error("[WorkflowOutputCollector] Failed to list files: #{e.message}")
    []
  end

  def collect_file(container_path)
    container_id = @step_run.terminal_session.container_id
    relative_path = container_path.sub("#{OUTPUTS_DIR}/", "")

    tempfile = Tempfile.new(["wf_output_", File.extname(relative_path)])
    begin
      DockerClient.copy_from(container_id, container_path, tempfile.path)
      file_size = File.size(tempfile.path)
      return nil if file_size > MAX_FILE_SIZE

      content_type = Marcel::MimeType.for(tempfile, name: relative_path)

      asset = @workflow_run.workflow_run_assets.create!(
        name: relative_path,
        produced_by_step_run: @step_run,
        content_type: content_type,
        file_size: file_size,
        s3_key: "workflow_runs/#{@workflow_run.id}/steps/#{@step_run.id}/#{relative_path}",
        file: tempfile
      )
      asset
    rescue StandardError => e
      Rails.logger.error("[WorkflowOutputCollector] Failed to collect #{relative_path}: #{e.message}")
      nil
    ensure
      tempfile.close
      tempfile.unlink
    end
  end
end
