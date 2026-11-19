# frozen_string_literal: true

module InternalTools
  # Promotes an output of the current workflow run into a durable, versioned
  # project-level asset. If a project asset with the same name and folder
  # already exists, a new version is appended instead of creating a duplicate
  # (see AssetExportService).
  #
  # The step's own outputs are read from the running container: they become
  # run outputs (WorkflowRunAsset) only when the session ends.
  class PromoteAsset < Base
    tool do
      display_name "Promote Asset"
      description "Promote a workflow output to a versioned project-level asset: a file this session wrote " \
                  "to #{Asset::OUTPUT_DIR}, or an output an earlier step of this run produced. " \
                  "If a project asset with the same name and folder already exists, a new version " \
                  "is added instead of creating a duplicate. " \
                  "Only use this tool when the step instructions explicitly ask to promote (or save/publish) " \
                  "an asset; do not call it on your own initiative."
      tags :assets
      inject_when :workflow_step_session
      param :name, type: :string, required: true,
                   description: "Name of the output to promote: its path relative to #{Asset::OUTPUT_DIR} " \
                                "(e.g. report.md or reports/q3.pdf)."
      param :folder, type: :string,
                     description: "Optional destination folder within project assets " \
                                  "(use / to nest, e.g. specs/api; no backslashes or control characters)."
    end

    def execute
      require_workflow_context!
      return error("No project in the current context") unless project

      source, failure = find_source
      return error(failure) unless source

      promoter = session_user
      return error("Cannot determine the promoting user") unless promoter

      if Asset.invalid_folder?(params[:folder])
        return error("Invalid folder '#{params[:folder]}': #{Folder::PATH_MESSAGE}, " \
                     "at most #{Asset::FOLDER_MAX_LENGTH} characters")
      end

      folder = Asset.normalize_folder(params[:folder])

      result = AssetExportService.new(source, project: project, user: promoter)
                                 .export!(folder: folder)

      asset = result[:asset]
      success({
        asset_id: asset.id,
        name: asset.name,
        folder: asset.folder,
        scope: asset.scope_indicator,
        version: result[:version]&.version,
        public: asset.public,
        share_url: asset.share_url
      }.to_json)
    end

    private

    # Returns [source, nil] or [nil, error message]. The file in this session's
    # outputs comes first: it is newer than any earlier step's output of the
    # same name.
    def find_source
      live, failure = read_live_output
      return [ nil, failure ] if failure
      return [ live, nil ] if live

      wra = find_workflow_run_asset
      return [ wra, nil ] if wra

      [ nil, "No output named '#{params[:name]}' in #{Asset::OUTPUT_DIR} or among this run's outputs" ]
    end

    def read_live_output
      path = live_output_path
      return [ nil, nil ] if path.nil? || session.try(:container_id).blank?

      read = ContainerRuntime.for_session(session).read_file_result(session.container_id, path)
      unless read.whole?
        return [ nil, "Could not read #{path} whole, so it was not promoted: #{read.reason}" ]
      end
      return [ nil, nil ] if read.content.nil?
      return [ nil, "#{path} is empty, so it was not promoted" ] if read.content.empty?

      name = path.delete_prefix("#{Asset::OUTPUT_DIR}/")
      [ AssetExportService::LiveOutput.new(name: name, content: read.content), nil ]
    end

    # nil for a name that would leave the outputs directory.
    def live_output_path
      path = Pathname.new("#{Asset::OUTPUT_DIR}/#{params[:name]}").cleanpath.to_s
      path if path.start_with?("#{Asset::OUTPUT_DIR}/")
    end

    def find_workflow_run_asset
      candidates = workflow_run.workflow_run_assets.where(name: params[:name])
      candidates.find_by(produced_by_step_run_id: step_run.id) ||
        candidates.order(created_at: :desc).first
    end
  end
end
