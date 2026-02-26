# frozen_string_literal: true

class ToolResult < ApplicationRecord
  include ToolResultUploader::Attachment(:stdout)
  include ToolResultUploader::Attachment(:stderr)
  include ToolResultUploader::Attachment(:result_data)
  include ToolResultUploader::Attachment(:output)

  belongs_to :tool
  belongs_to :terminal_session, optional: true
  belongs_to :step_run, optional: true

  validates :execution_id, presence: true, uniqueness: true
  validates :state, presence: true, inclusion: {
    in: %w[processing completed failed expired]
  }

  scope :stale, ->(age) { where(state: %w[completed failed]).where("created_at < ?", age.ago) }

  def self.generate_id
    "tr-#{SecureRandom.hex(12)}"
  end

  def complete!(exit_code:, stdout:, stderr:, duration_ms:, error: nil)
    self.state = error.nil? && exit_code == 0 ? "completed" : "failed"
    self.exit_code = exit_code
    self.error = error || (exit_code != 0 ? "Exited with code #{exit_code}" : nil)
    self.duration_ms = duration_ms

    self.stdout = upload_string(stdout, "stdout.txt") if stdout.present?
    self.stderr = upload_string(stderr, "stderr.txt") if stderr.present?

    parsed = try_parse_json(stdout)
    self.result_data = upload_string(parsed.to_json, "result_data.json") if parsed

    save!
  end

  def attach_output_files(container, paths, runtime)
    collected = {}
    paths.each do |path|
      content = read_file_from_container(container, path, runtime)
      collected[File.basename(path)] = content if content.present?
    end
    return if collected.empty?

    archive = TarGzPacker.pack(collected)
    self.output = { io: StringIO.new(archive), filename: "output.tar.gz",
                    content_type: "application/gzip" }
    save!
  end

  private

  def upload_string(content, filename)
    ToolResultUploader.upload(StringIO.new(content), :store,
      metadata: { "filename" => filename, "size" => content.bytesize })
  end

  def try_parse_json(text)
    return nil if text.blank?
    parsed = JSON.parse(text)
    parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def read_file_from_container(container, path, runtime)
    result = runtime.exec(container, ["cat", path])
    return nil unless result[2].zero?
    result[0].join
  rescue StandardError
    nil
  end
end
