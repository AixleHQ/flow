# frozen_string_literal: true

module ProjectMove
  # Company assets stay with the company that owns them. A moving project takes a
  # copy of each one its workflows point at, and its references move to the copy.
  #
  # Copies are made before the move's transaction — a file upload has no place
  # inside one — and rewritten into references inside it. When the move fails, the
  # caller discards the copies; the rewrite rolls back with everything else.
  class AssetCopier
    attr_reader :copies

    def initialize(project:, assets:, source:)
      @project = project
      @assets = assets
      @source = source
      @copies = {}
    end

    def copy!
      @assets.each { |asset| @copies[asset.id] = copy(asset) }
      self
    end

    def discard!
      @copies.each_value(&:destroy!)
      @copies = {}
    end

    def rewrite_references!
      return if @copies.empty?

      steps = Step.unscoped.where(workflow_id: workflow_ids)
      steps.find_each do |step|
        changes = { asset_ids: rewrite_ids(step.asset_ids), instructions: rewrite_text(step.instructions) }
                  .select { |attribute, value| value != step.public_send(attribute) }
        step.update_columns(changes) if changes.any?
      end
      SubStep.where(step_id: steps.select(:id)).find_each do |sub_step|
        text = rewrite_text(sub_step.instructions)
        sub_step.update_columns(instructions: text) if text != sub_step.instructions
      end
      Workflow.where(id: workflow_ids).find_each do |workflow|
        ids = rewrite_ids(workflow.base_asset_ids)
        workflow.update_columns(config: workflow.config.merge("base_asset_ids" => ids)) if ids != workflow.base_asset_ids
      end
    end

    private

    def copy(asset)
      copy = Asset.create!(scope: @project, name: free_name(asset), folder: asset.folder, tags: asset.tags,
                           created_by: asset.created_by)
      latest = asset.latest_version
      return copy if latest.nil?

      version = copy.versions.build(source: latest.source, content_type: latest.content_type,
                                    file_size: latest.file_size, uploaded_by: latest.uploaded_by)
      # An object of its own, not the source's stored file: deleting either asset
      # would otherwise delete the other's bytes.
      version.file_attacher.attach(latest.file) if latest.file.present?
      version.save!
      copy
    end

    def free_name(asset)
      taken = Asset.where(scope: @project, folder: asset.folder, deleted_at: nil).pluck(:name).to_set
      return asset.name unless taken.include?(asset.name)

      extension = File.extname(asset.name)
      base = asset.name.delete_suffix(extension)
      "#{base} (#{@source.name})#{extension}"
    end

    def rewrite_ids(ids)
      Array(ids).map { |id| @copies[id.to_i]&.id || id }
    end

    def rewrite_text(text)
      InstructionReferences.rewrite(text) do |ref|
        copy = ref.type == "asset" && @copies[ref.id]
        "{{asset:#{copy.id}}}" if copy
      end
    end

    def workflow_ids
      @workflow_ids ||= Workflow.where(scope_type: "Project", scope_id: @project.id).pluck(:id)
    end
  end
end
