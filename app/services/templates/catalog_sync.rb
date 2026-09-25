# frozen_string_literal: true

module Templates
  # Mirrors the public templates repository into catalog_namespaces and
  # catalog_templates.
  #
  # One commit per run: resolve the branch head, download that commit's tarball,
  # read the publishers from namespaces.yaml, validate every
  # templates/<namespace>/<slug>/ with this installation's own schema, and
  # upsert. A template that fails validation — or sits under a namespace that is
  # not registered — is skipped and reported, never half-mirrored; one that
  # disappeared from the repository (or is listed in revoked.yaml) is marked
  # revoked rather than deleted, so the provenance of past installs stays
  # resolvable (design D18).
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

    # templates/<namespace>/<slug>/<rest> → { "namespace/slug" => { rest => bytes } }
    def self.group_packages(tree)
      tree.each_with_object(Hash.new { |h, k| h[k] = {} }) do |(path, bytes), acc|
        dir, namespace, slug, rest = path.split("/", 4)
        next unless dir == TEMPLATES_DIR && namespace.present? && slug.present? && rest.present?

        acc["#{namespace}/#{slug}"][rest] = bytes
      end
    end

    def initialize(client: RepositoryClient.new, now: Time.current)
      @client = client
      @now = now
    end

    def call
      sha = @client.head_sha
      return Result.new(commit_sha: sha, upserted: 0, skipped: [], revoked: 0, unchanged: true) if mirrored?(sha)

      tree = Tarball.extract(@client.tarball(sha))
      registry = NamespaceRegistry.parse(tree[NamespaceRegistry::FILE])
      revocations = parse_revocations(tree[REVOKED_FILE])
      packages = self.class.group_packages(tree)
      skipped = registry.errors.map { |error| { identifier: NamespaceRegistry::FILE, reason: error } }
      upserted = 0
      revoked = 0

      CatalogTemplate.transaction do
        sync_namespaces(registry)
        packages.each do |identifier, files|
          package = build_package(identifier, files, registry, skipped) or next
          upsert(package, sha, revocations[identifier])
          upserted += 1
        end
        revoked = revoke_missing(present: packages.keys, revocations: revocations)
      end
      Result.new(commit_sha: sha, upserted: upserted, skipped: skipped, revoked: revoked, unchanged: false)
    end

    private

    def mirrored?(sha)
      CatalogTemplate.exists? && CatalogTemplate.listed.where.not(commit_sha: sha).none? &&
        CatalogTemplate.exists?(commit_sha: sha)
    end

    def sync_namespaces(registry)
      registry.entries.each_value do |entry|
        row = CatalogNamespace.find_or_initialize_by(name: entry.name)
        row.update!(display_name: entry.display_name, url: entry.url, verified: entry.verified,
                    owners: entry.owners, synced_at: @now)
      end
      CatalogNamespace.where.not(name: registry.names).delete_all
    end

    def build_package(identifier, files, registry, skipped)
      namespace, slug = identifier.split("/", 2)
      return skip(skipped, identifier, "namespace #{namespace} is not registered in #{NamespaceRegistry::FILE}") unless registry[namespace]

      yaml = files.delete(Package::DEFINITION_FILE)
      return skip(skipped, identifier, "no #{Package::DEFINITION_FILE}") unless yaml
      return skip(skipped, identifier, "larger than #{MAX_TEMPLATE_BYTES} bytes") if files.values.sum(&:bytesize) > MAX_TEMPLATE_BYTES

      package = Package.new(definition: Package.parse_definition(yaml.force_encoding(Encoding::UTF_8)), files: files)
      if package.namespace != namespace || package.slug != slug
        return skip(skipped, identifier, "directory does not match namespace/slug #{package.identifier.inspect}")
      end

      errors = Validator.new(package).errors
      return skip(skipped, identifier, errors.join("; ")) if errors.any?

      package
    rescue Psych::Exception => e
      skip(skipped, identifier, "#{Package::DEFINITION_FILE}: #{e.message}")
    end

    def skip(skipped, identifier, reason)
      Rails.logger.warn("[Templates::CatalogSync] skipped #{identifier}: #{reason}")
      skipped << { identifier: identifier, reason: reason }
      nil
    end

    def upsert(package, sha, revocation_reason)
      row = CatalogTemplate.find_or_initialize_by(namespace: package.namespace, slug: package.slug)
      row.assign_package(package, commit_sha: sha, synced_at: @now)
      row.assign_attributes(revoked_at: revocation_reason ? (row.revoked_at || @now) : nil, revocation_reason: revocation_reason)
      row.save!
    end

    def revoke_missing(present:, revocations:)
      scope = CatalogTemplate.listed.where.not(
        "(namespace || '/' || slug) IN (?)", present.presence || [ "" ]
      )
      count = scope.count
      scope.find_each do |row|
        row.update!(revoked_at: @now, revocation_reason: revocations[row.identifier] || REMOVED_REASON)
      end
      count
    end

    # revoked.yaml: a list of { template: namespace/slug, reason: }
    def parse_revocations(yaml)
      return {} if yaml.blank?

      entries = YAML.safe_load(yaml.force_encoding(Encoding::UTF_8), permitted_classes: [], aliases: false)
      Array(entries).each_with_object({}) do |entry, acc|
        next unless entry.is_a?(Hash) && entry["template"].to_s.include?("/")

        acc[entry["template"].to_s] = entry["reason"].presence || "Revoked by the maintainers."
      end
    rescue Psych::Exception => e
      Rails.logger.error("[Templates::CatalogSync] #{REVOKED_FILE} is unreadable, revocations not applied: #{e.message}")
      {}
    end
  end
end
