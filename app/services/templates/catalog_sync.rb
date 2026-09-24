# frozen_string_literal: true

module Templates
  # Mirrors the public templates repository into catalog_templates.
  #
  # One commit per run: resolve the branch head, download that commit's tarball,
  # validate every template in it with this installation's own schema, and
  # upsert. A template that fails validation is skipped and reported, never
  # half-mirrored; one that disappeared from the repository (or is listed in
  # revoked.yaml) is marked revoked rather than deleted, so the provenance of
  # past installs stays resolvable (design D18).
  #
  # Idempotent: a run at an already-mirrored commit changes nothing.
  class CatalogSync
    TEMPLATES_DIR = "templates"
    REVOKED_FILE = "revoked.yaml"
    MAX_TEMPLATE_BYTES = 5.megabytes
    REMOVED_REASON = "Removed from the templates repository."

    Result = Struct.new(:commit_sha, :upserted, :skipped, :revoked, :unchanged, keyword_init: true) do
      def to_s = "commit=#{commit_sha} upserted=#{upserted} skipped=#{skipped.size} revoked=#{revoked} unchanged=#{unchanged}"
    end

    def self.call(...) = new(...).call

    def initialize(client: RepositoryClient.new, now: Time.current)
      @client = client
      @now = now
    end

    def call
      sha = @client.head_sha
      return Result.new(commit_sha: sha, upserted: 0, skipped: [], revoked: 0, unchanged: true) if mirrored?(sha)

      tree = Tarball.extract(@client.tarball(sha))
      revocations = parse_revocations(tree[REVOKED_FILE])
      skipped = []
      upserted = 0
      revoked = 0

      CatalogTemplate.transaction do
        packages(tree).each do |slug, files|
          package = build_package(slug, files, skipped) or next
          upsert(package, sha, revocations[slug])
          upserted += 1
        end
        revoked = revoke_missing(present_slugs: packages(tree).keys, revocations: revocations)
      end
      Result.new(commit_sha: sha, upserted: upserted, skipped: skipped, revoked: revoked, unchanged: false)
    end

    private

    def mirrored?(sha)
      CatalogTemplate.exists? && CatalogTemplate.listed.where.not(commit_sha: sha).none? &&
        CatalogTemplate.exists?(commit_sha: sha)
    end

    # slug → { relative path → bytes } for every templates/<slug>/ directory
    def packages(tree)
      @packages ||= tree.each_with_object(Hash.new { |h, k| h[k] = {} }) do |(path, bytes), acc|
        dir, slug, rest = path.split("/", 3)
        next unless dir == TEMPLATES_DIR && slug.present? && rest.present?

        acc[slug][rest] = bytes
      end
    end

    def build_package(slug, files, skipped)
      yaml = files.delete(Package::DEFINITION_FILE)
      return skip(skipped, slug, "no #{Package::DEFINITION_FILE}") unless yaml
      return skip(skipped, slug, "larger than #{MAX_TEMPLATE_BYTES} bytes") if files.values.sum(&:bytesize) > MAX_TEMPLATE_BYTES

      package = Package.new(definition: Package.parse_definition(yaml.force_encoding(Encoding::UTF_8)), files: files)
      return skip(skipped, slug, "directory name does not match slug #{package.slug.inspect}") if package.slug != slug

      errors = Validator.new(package).errors
      return skip(skipped, slug, errors.join("; ")) if errors.any?

      package
    rescue Psych::Exception => e
      skip(skipped, slug, "#{Package::DEFINITION_FILE}: #{e.message}")
    end

    def skip(skipped, slug, reason)
      Rails.logger.warn("[Templates::CatalogSync] skipped #{slug}: #{reason}")
      skipped << { slug: slug, reason: reason }
      nil
    end

    def upsert(package, sha, revocation_reason)
      row = CatalogTemplate.find_or_initialize_by(slug: package.slug)
      row.assign_attributes(
        version: package.version,
        name: package.name,
        summary: package.definition["summary"],
        kind: package.kind,
        categories: Array(package.definition["categories"]),
        format_version: package.definition["format_version"],
        definition: package.definition,
        files: CatalogTemplate.serialize_files(package),
        readme: package.readme,
        setup_markdown: package.setup_markdown,
        commit_sha: sha,
        package_digest: package.digest,
        installable: package.definition["format_version"] == Package::FORMAT_VERSION,
        revoked_at: revocation_reason ? (row.revoked_at || @now) : nil,
        revocation_reason: revocation_reason,
        synced_at: @now
      )
      row.save!
    end

    def revoke_missing(present_slugs:, revocations:)
      scope = CatalogTemplate.listed.where.not(slug: present_slugs)
      count = scope.count
      scope.find_each do |row|
        row.update!(revoked_at: @now, revocation_reason: revocations[row.slug] || REMOVED_REASON)
      end
      count
    end

    # revoked.yaml: a list of { slug:, reason: }
    def parse_revocations(yaml)
      return {} if yaml.blank?

      entries = YAML.safe_load(yaml.force_encoding(Encoding::UTF_8), permitted_classes: [], aliases: false)
      Array(entries).each_with_object({}) do |entry, acc|
        next unless entry.is_a?(Hash) && entry["slug"].present?

        acc[entry["slug"].to_s] = entry["reason"].presence || "Revoked by the maintainers."
      end
    rescue Psych::Exception => e
      Rails.logger.error("[Templates::CatalogSync] #{REVOKED_FILE} is unreadable, revocations not applied: #{e.message}")
      {}
    end
  end
end
