# frozen_string_literal: true

# The one place a repository's checkout path is decided.
#
# Historically the path was recomputed from `repo.repo_name` wherever it was
# needed (clone, context rendering, the GitHub token refresh tool), which has two
# failure modes: two repositories named `api` — including two on different hosts
# — resolve to the same directory and silently overwrite each other, and a
# renamed remote repository moves the computed path out from under a live
# session.
#
# So the path is computed ONCE at provisioning time, persisted in session
# metadata, and read back everywhere else. Existing sessions keep the paths they
# were created with; nothing recomputes a path for a checkout that already
# exists.
class RepositoryWorkspacePath
  ROOT = "/workspace/repo"
  METADATA_KEY = "repository_paths"

  class << self
    # Resolve paths for a whole set at once, because collision detection is a
    # property of the set, not of one repository.
    #
    # A repository whose basename is unique keeps the bare, familiar path. Only
    # the ones that would collide — and every Azure row, whose display names may
    # contain spaces — get an id-qualified directory.
    def resolve(repositories)
      repos = Array(repositories)
      counts = repos.group_by { |r| basename(r) }.transform_values(&:size)

      repos.to_h do |repo|
        base = basename(repo)
        path = if counts[base].to_i > 1 || qualify?(repo)
          "#{ROOT}/#{qualified_name(repo, base)}"
        else
          "#{ROOT}/#{base}"
        end
        [ repo.id, path ]
      end
    end

    # Persisted map wins over any recomputation: it is the record of where the
    # files actually are.
    def for_session(session, repositories)
      stored = stored_map(session)
      resolved = resolve(repositories)
      resolved.merge(stored.slice(*resolved.keys))
    end

    def persist!(session, path_map)
      metadata = session.metadata || {}
      metadata[METADATA_KEY] = (metadata[METADATA_KEY] || {}).merge(path_map.transform_keys(&:to_s))
      session.update_column(:metadata, metadata)
      metadata[METADATA_KEY]
    end

    def stored_map(session)
      (session&.metadata || {}).fetch(METADATA_KEY, {}).to_h { |k, v| [ k.to_i, v.to_s ] }
    end

    # Path for one repository in a session, falling back to the stand-alone
    # resolution when a session predates the stored map.
    def for_repository(session, repository)
      stored_map(session)[repository.id] || resolve([ repository ]).fetch(repository.id)
    end

    private

    def basename(repo)
      sanitize(repo.repo_name.presence || "repo")
    end

    # Azure display names may contain spaces and other characters that make a
    # bare directory awkward to type and ambiguous to match, and two Azure
    # projects in one organization may both hold an `api`. Qualifying them
    # unconditionally keeps Azure paths predictable instead of depending on
    # which other repositories happen to be attached.
    def qualify?(repo)
      repo.respond_to?(:azure_devops?) && repo.azure_devops?
    end

    def qualified_name(repo, base)
      prefix = qualify?(repo) ? "azure-" : ""
      "#{prefix}#{repo.id}-#{base}"
    end

    # Anything that is not a safe directory atom collapses to a dash. The result
    # still reaches a shell command line, so it is built from an allowlist rather
    # than by removing known-bad characters.
    def sanitize(name)
      cleaned = name.to_s.strip.gsub(/[^a-zA-Z0-9._-]+/, "-").gsub(/\A[-.]+|[-.]+\z/, "").presence || "repo"
      cleaned.truncate(80, omission: "")
    end
  end
end
