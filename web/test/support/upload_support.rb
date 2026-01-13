module UploadSupport
  IMAGE_FILE_PATH = "test/files/test.png".freeze
  IMAGE_METADATA = { "mime_type" => "image/png", "filename" => "test.png" }.freeze

  PROJECT_FILE_PATH = "test/files/sample_project.zip".freeze
  PROJECT_METADATA = { "mime_type" => "application/zip", "filename" => "sample_project.zip" }.freeze

  PROJECT_TAR_FILE_PATH = "test/files/sample_project.tar.gz".freeze
  PROJECT_TAR_METADATA = { "mime_type" => "application/tar+gzip", "filename" => "sample_project.tar.gz" }.freeze

  IMAGE_COLLECTION_FILE_PATH = "test/files/sample_images.zip".freeze
  IMAGE_COLLECTION_METADATA = { "mime_type" => "application/zip", "filename" => "sample_images.zip" }.freeze

  DOCUMENT_FILE_PATH = "test/files/sample_document.md".freeze
  DOCUMENT_METADATA = { "mime_type" => "text/markdown", "filename" => "sample_document.md" }.freeze

  EXTERNAL_SPEC_FILE_PATH = "test/files/v2_spec.json".freeze
  EXTERNAL_SPEC_METADATA = { "mime_type" => "application/json", "filename" => "v2_spec.json" }.freeze

  def image_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, IMAGE_FILE_PATH, IMAGE_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def image_file_cache_data
    uploaded_file = uploaded_file(:cache, IMAGE_FILE_PATH, IMAGE_METADATA)
    uploaded_file.data
  end

  def project_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, PROJECT_FILE_PATH, PROJECT_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def project_file_cache_data
    uploaded_file = uploaded_file(:cache, PROJECT_FILE_PATH, PROJECT_METADATA)
    uploaded_file.data
  end

  def project_tar_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, PROJECT_TAR_FILE_PATH, PROJECT_TAR_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def project_tar_file_cache_data
    uploaded_file = uploaded_file(:cache, PROJECT_TAR_FILE_PATH, PROJECT_TAR_METADATA)
    uploaded_file.data
  end

  def image_collection_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, IMAGE_COLLECTION_FILE_PATH, IMAGE_COLLECTION_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def image_collection_file_cache_data
    uploaded_file = uploaded_file(:cache, IMAGE_COLLECTION_FILE_PATH, IMAGE_COLLECTION_METADATA)
    uploaded_file.data
  end

  def document_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, DOCUMENT_FILE_PATH, DOCUMENT_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def document_file_cache_data
    uploaded_file = uploaded_file(:cache, DOCUMENT_FILE_PATH, DOCUMENT_METADATA)
    uploaded_file.data
  end

  def external_spec_file_store_data
    attacher = Shrine::Attacher.new
    attacher.set(uploaded_file(:store, EXTERNAL_SPEC_FILE_PATH, EXTERNAL_SPEC_METADATA))
    attacher.column_data # or attacher.data in case of postgres jsonb column
  end

  def external_spec_file_cache_data
    uploaded_file = uploaded_file(:cache, EXTERNAL_SPEC_FILE_PATH, EXTERNAL_SPEC_METADATA)
    uploaded_file.data
  end

  private

  def uploaded_file(store, filepath, metadata)
    file = File.open(filepath, binmode: true)
    # for performance we skip metadata extraction and assign test metadata
    uploaded_file = Shrine.upload(file, store, metadata: false)

    uploaded_file.metadata.merge!(
      "size" => File.size(file.path),
      **metadata,
    )

    uploaded_file
  end
end
