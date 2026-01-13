# frozen_string_literal: true

module TemporalStubs
  # Stub Temporal workflows to avoid requiring a running worker in most tests
  def stub_temporal_workflows
    helper = self

    TemporalService.stubs(:start_workflow).with do |workflow, input, *args|
      # Simulate side effects of asset processing workflows
      case workflow.name
      when "asset_codebase_processing"
        asset = Asset.find_by(id: input)
        if asset
          # Create code_base if it doesn't exist
          code_base = asset.code_base || asset.create_code_base!(name: asset.name, status: :draft)
          # Create sample items to simulate extraction
          helper.create_sample_code_base_items(code_base) if code_base.items.empty?
        end
      when "asset_image_collection_processing"
        asset = Asset.find_by(id: input)
        if asset
          # Create image_collection if it doesn't exist
          image_collection = asset.image_collection || asset.create_image_collection!(name: asset.name, status: :draft)
          # Create sample items to simulate extraction
          helper.create_sample_image_collection_items(image_collection) if image_collection.items.empty?
        end
      when "integration_repo_download"
        repo = Integration::Repo.find_by(id: input)
        if repo && repo.asset
          # Create code_base for the downloaded repo
          code_base = repo.asset.code_base || repo.asset.create_code_base!(name: repo.asset.name, status: :draft)
          helper.create_sample_code_base_items(code_base) if code_base.items.empty?
          # Mark repo as completed
          repo.update(status: :completed) if repo.may_complete?
        end
      when "jira_export"
        # Execute Jira export inline
        Activities::Integration::Jira::Export.new.run(input)
      when "jira_import"
        # Execute Jira import inline
        Activities::Integration::Jira::Import.new.run(input)
      when "jira_sync_projects"
        # Execute Jira sync inline
        Activities::Integration::Jira::SyncProjects.new.run(input)
      when "jira_cleanup"
        # Execute Jira cleanup inline
        Activities::Integration::Jira::Cleanup.new.run(input)
      when "confluence_import"
        # Execute Confluence import inline
        Activities::Integration::Confluence::Import.new.run(input)
      when "confluence_sync_spaces"
        # Execute Confluence sync inline
        Activities::Integration::Confluence::SyncSpaces.new.run(input)
      end
      true
    end.returns(
      { ok: true, workflow_id: "test-workflow-#{SecureRandom.uuid}", run_id: "test-run-#{SecureRandom.uuid}" }
    )

    TemporalService.stubs(:execute_workflow).returns(nil)
  end

  def create_sample_code_base_items(code_base)
    # Create sample file structure that matches test expectations
    sample_files = [
      { filename: "index.js", full_path: "src/index.js", file_type: "file" },
      { filename: "App.js", full_path: "src/components/App.js", file_type: "file" },
      { filename: "helper.js", full_path: "src/utils/helper.js", file_type: "file" },
      { filename: "index.test.js", full_path: "test/index.test.js", file_type: "file" },
      { filename: "package.json", full_path: "package.json", file_type: "file" },
      { filename: "README.md", full_path: "README.md", file_type: "file" },
      { filename: "src", full_path: "src", file_type: "directory" },
      { filename: "components", full_path: "src/components", file_type: "directory" },
      { filename: "utils", full_path: "src/utils", file_type: "directory" },
      { filename: "test", full_path: "test", file_type: "directory" },
      { filename: ".gitignore", full_path: ".gitignore", file_type: "file" }
    ]

    sample_files.each do |file_data|
      code_base.items.create!(
        filename: file_data[:filename],
        full_path: file_data[:full_path],
        file_type: file_data[:file_type],
        file: create_dummy_text_file(file_data[:filename])
      )
    end
  end

  def create_sample_image_collection_items(image_collection)
    # Create sample image files
    sample_images = [
      { filename: "screenshot1.png", full_path: "screenshot1.png", file_type: "file" },
      { filename: "screenshot2.png", full_path: "screenshot2.png", file_type: "file" },
      { filename: "screenshot3.png", full_path: "screenshot3.png", file_type: "file" },
      { filename: "logo.png", full_path: "logo.png", file_type: "file" },
      { filename: "icon.png", full_path: "icon.png", file_type: "file" }
    ]

    sample_images.each do |image_data|
      image_collection.items.create!(
        filename: image_data[:filename],
        full_path: image_data[:full_path],
        file_type: image_data[:file_type],
        file: create_dummy_image_file
      )
    end
  end

  private

  def create_dummy_text_file(filename)
    # Create a temporary file with sample content
    tempfile = Tempfile.new([ filename, ".txt" ])
    tempfile.write("// Sample content for #{filename}\n")
    tempfile.rewind

    # Upload to Shrine's cache storage
    uploaded_file = Shrine.upload(tempfile, :cache, metadata: {
      "filename" => filename,
      "mime_type" => "text/plain",
      "size" => tempfile.size
    })

    tempfile.close
    tempfile.unlink

    uploaded_file
  end

  def create_dummy_image_file
    # Upload the existing test image file to Shrine's cache
    file = File.open("test/files/test.png", "rb")
    uploaded_file = Shrine.upload(file, :cache, metadata: {
      "filename" => "test.png",
      "mime_type" => "image/png",
      "size" => file.size
    })
    file.close

    uploaded_file
  end
end
