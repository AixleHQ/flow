# frozen_string_literal: true

class WorkspacePreparator
  INPUT_DIR = "/workspace/input"
  OUTPUTS_DIR = "/workspace/outputs"

  def initialize(step_run)
    @step_run = step_run
    @workflow_run = step_run.workflow_run
    @step = step_run.step
  end

  def prepare!(container_id)
    ensure_directories(container_id)
    mount_workflow_run_assets(container_id)
    mount_project_assets(container_id)
    generate_index(container_id)
    resolve_instructions
  end

  def resolve_instructions
    instructions = @step.instructions.to_s
    return instructions if instructions.blank?

    available_assets = build_asset_map
    instructions.gsub(/\{\{(\w+)\}\}/) do |match|
      asset_name = ::Regexp.last_match(1)
      path = available_assets[asset_name]
      path ? "#{INPUT_DIR}/#{path}" : match
    end
  end

  private

  def ensure_directories(container_id)
    DockerClient.exec(container_id, "mkdir -p #{INPUT_DIR} #{OUTPUTS_DIR}")
  end

  def mount_workflow_run_assets(container_id)
    previous_assets = @workflow_run.workflow_run_assets
                                   .where.not(produced_by_step_run_id: @step_run.id)

    previous_assets.find_each do |asset|
      next unless asset.file

      tempfile = Tempfile.new([ "wf_input_", File.extname(asset.name) ])
      begin
        asset.file.download { |tf| FileUtils.cp(tf.path, tempfile.path) }
        target_path = "#{INPUT_DIR}/#{asset.name}"
        DockerClient.exec(container_id, "mkdir -p #{File.dirname(target_path)}")
        DockerClient.copy_to(container_id, tempfile.path, target_path)
      ensure
        tempfile.close
        tempfile.unlink
      end
    end
  end

  def mount_project_assets(container_id)
    asset_ids = @workflow_run.input_asset_ids
    return if asset_ids.blank?

    assets = Asset.where(id: asset_ids)
    assets.find_each do |asset|
      version = asset.current_version
      next unless version&.file

      tempfile = Tempfile.new([ "proj_input_", File.extname(asset.name) ])
      begin
        version.file.download { |tf| FileUtils.cp(tf.path, tempfile.path) }
        target_path = "#{INPUT_DIR}/#{asset.name}"
        DockerClient.exec(container_id, "mkdir -p #{File.dirname(target_path)}")
        DockerClient.copy_to(container_id, tempfile.path, target_path)
      ensure
        tempfile.close
        tempfile.unlink
      end
    end
  end

  def generate_index(container_id)
    content = build_index_content
    tempfile = Tempfile.new([ "_index_", ".md" ])
    begin
      tempfile.write(content)
      tempfile.flush
      DockerClient.copy_to(container_id, tempfile.path, "#{INPUT_DIR}/_index.md")
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def build_index_content
    lines = [ "# Workspace Input Index\n" ]

    project_assets = build_project_assets_section
    unless project_assets.empty?
      lines << "## Project Assets (selected at workflow start)\n"
      lines.concat(project_assets)
      lines << ""
    end

    run_assets = build_run_assets_section
    unless run_assets.empty?
      lines << "## Workflow Run Assets (from previous steps)\n"
      lines.concat(run_assets)
      lines << ""
    end

    lines << "## Instructions\n"
    lines << "- Read from: #{INPUT_DIR}/"
    lines << "- Save all results to: #{OUTPUTS_DIR}/"
    lines << "- If you need to modify an existing document, copy from input to outputs first"

    lines.join("\n")
  end

  def build_project_assets_section
    asset_ids = @workflow_run.input_asset_ids
    return [] if asset_ids.blank?

    Asset.where(id: asset_ids).map do |asset|
      version = asset.current_version
      size = version ? human_file_size(version.file_size || 0) : "unknown"
      "- **#{asset.name}** — #{asset.asset_type || 'file'} (#{size})"
    end
  end

  def build_run_assets_section
    @workflow_run.workflow_run_assets
                 .where.not(produced_by_step_run_id: @step_run.id)
                 .includes(produced_by_step_run: :step)
                 .map do |asset|
      source = asset.produced_by_step_run&.step&.name || "unknown"
      size = human_file_size(asset.file_size || 0)
      "- **#{asset.name}** — from \"#{source}\" (#{asset.content_type || 'file'}, #{size})"
    end
  end

  def build_asset_map
    map = {}

    @workflow_run.workflow_run_assets
                 .where.not(produced_by_step_run_id: @step_run.id)
                 .each do |asset|
      basename = File.basename(asset.name, File.extname(asset.name))
      map[basename] = asset.name
    end

    asset_ids = @workflow_run.input_asset_ids
    if asset_ids.present?
      Asset.where(id: asset_ids).each do |asset|
        basename = File.basename(asset.name, File.extname(asset.name))
        map[basename] = asset.name
      end
    end

    map
  end

  def human_file_size(bytes)
    if bytes < 1024
      "#{bytes}B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(1)}KB"
    else
      "#{(bytes / (1024.0 * 1024)).round(1)}MB"
    end
  end
end
