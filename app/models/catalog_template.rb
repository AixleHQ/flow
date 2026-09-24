# frozen_string_literal: true

# CatalogTemplate — this installation's mirror of one template from the public
# templates repository (Templates::CatalogSync). Global, not tenant data.
#
# The row IS the reviewed package: installs read `definition` and `files` from
# here and never fetch anything live, so what gets installed is what was merged
# at `commit_sha` (design D17).
class CatalogTemplate < ApplicationRecord
  validates :slug, presence: true, uniqueness: true
  validates :name, :commit_sha, :package_digest, :synced_at, presence: true
  validates :version, :format_version, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, inclusion: { in: Templates::Package::KINDS }

  scope :listed, -> { where(revoked_at: nil) }

  def revoked? = revoked_at.present?

  # Copies a validated package into this row, as mirrored at `commit_sha`.
  def assign_package(package, commit_sha:, synced_at: Time.current)
    assign_attributes(
      slug: package.slug, version: package.version, name: package.name,
      summary: package.definition["summary"], kind: package.kind,
      categories: Array(package.definition["categories"]),
      format_version: package.definition["format_version"],
      definition: package.definition, files: self.class.serialize_files(package),
      readme: package.readme, setup_markdown: package.setup_markdown,
      commit_sha: commit_sha, package_digest: package.digest,
      installable: package.definition["format_version"] == Templates::Package::FORMAT_VERSION,
      synced_at: synced_at
    )
    self
  end

  def to_package
    Templates::Package.new(
      definition: definition,
      files: files.transform_values { |file| Base64.strict_decode64(file.fetch("base64")) }
    )
  end

  # Stored form of a package's files: bytes are base64 so binary files survive
  # the jsonb round trip, and each keeps the hash it was mirrored with.
  def self.serialize_files(package)
    package.files.to_h do |path, bytes|
      [ path, { "base64" => Base64.strict_encode64(bytes), "sha256" => Digest::SHA256.hexdigest(bytes), "size" => bytes.bytesize } ]
    end
  end
end
