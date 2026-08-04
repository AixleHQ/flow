# frozen_string_literal: true

module Skills
  # Parses and validates a SKILL.md against the Agent Skills specification
  # (agentskills.io), which is an open standard adopted well beyond Claude.
  #
  # Used for two different jobs, deliberately with different strictness:
  #
  #   parse(content) — authoring. Everything the spec requires is enforced, because
  #     a hand-written skill's `name` becomes its directory name in the container
  #     and the spec requires the two to match exactly. A name that does not match
  #     fails to load in the agent, silently.
  #
  #   name/description(content) — reading someone else's skill for catalog metadata.
  #     Lenient: we are describing what upstream published, not approving it.
  #
  # No Ruby validator exists to lean on. The reference implementation `skills-ref`
  # is Python (`agentskills validate path/to/skill`), with a Rust crate and several
  # npm/GitHub-Action validators besides — all of them a subprocess away, which is
  # more machinery than the rules themselves.
  class SkillMarkdown
    MAX_NAME_LENGTH = 64
    MAX_DESCRIPTION_LENGTH = 1024
    # The spec recommends keeping SKILL.md under 500 lines and the instruction body
    # under ~5000 tokens, because the whole body is loaded once a skill activates.
    MAX_BODY_LINES = 500
    MAX_BODY_BYTES = 40_000
    # Frontmatter is capped separately: body limits alone would let a multi-megabyte
    # `description` (or any other key) through, and the whole file gets written into
    # every container the project runs.
    MAX_FRONTMATTER_BYTES = 8_000
    NAME_FORMAT = ::Skill::MANUAL_NAME_FORMAT

    Result = Struct.new(:name, :description, :frontmatter, :content, :errors, keyword_init: true) do
      def valid?
        errors.empty?
      end

      def error_sentence
        errors.join("; ")
      end
    end

    class << self
      def parse(content)
        # A paste routinely arrives with a UTF-8 BOM or a leading blank line. Refusing
        # it with "must start with YAML frontmatter" when the frontmatter is plainly
        # there reads as a bug in us. The normalised form is what gets stored, so the
        # file written into the container starts with `---`.
        content = normalize(content)
        errors = []

        raw_frontmatter = extract_frontmatter(content)
        if raw_frontmatter.nil?
          return Result.new(errors: [ "SKILL.md must start with YAML frontmatter delimited by ---" ], content: content)
        end

        # The spec warns that angle brackets in frontmatter "can inject unintended
        # instructions into the system prompt". A skill is prompt content by design;
        # this is the one place we can cheaply refuse a hostile shape.
        errors << "frontmatter must not contain < or >" if raw_frontmatter.match?(/[<>]/)
        if raw_frontmatter.bytesize > MAX_FRONTMATTER_BYTES
          errors << "frontmatter is too large (limit #{MAX_FRONTMATTER_BYTES} bytes)"
        end

        meta = safe_yaml(raw_frontmatter)
        errors << "frontmatter must be a YAML mapping" unless meta.is_a?(Hash)
        meta = {} unless meta.is_a?(Hash)

        name = meta["name"].to_s.strip
        description = meta["description"].to_s.strip
        body = content.split(/^---\s*$/, 3)[2].to_s.strip

        errors.concat(name_errors(name))
        errors.concat(description_errors(description))
        errors.concat(body_errors(body))

        Result.new(
          name: name.presence,
          description: description.presence,
          frontmatter: meta,
          content: content,
          errors: errors
        )
      end

      # Lenient read of a foreign SKILL.md, for catalog metadata.
      def name(content)
        meta = safe_yaml(extract_frontmatter(content))
        return nil unless meta.is_a?(Hash)

        (meta["name"].presence || meta["title"].presence)&.to_s&.strip&.truncate(MAX_NAME_LENGTH)
      end

      def description(content)
        meta = safe_yaml(extract_frontmatter(content))
        return nil unless meta.is_a?(Hash)

        meta["description"].presence&.to_s&.strip&.truncate(MAX_DESCRIPTION_LENGTH)
      end

      # Does this SKILL.md belong to the slug we asked for?
      #
      # This is the ONLY reliable identity check available when reading someone else's
      # repository: a registry slug is derived from the frontmatter `name` upstream, so
      # the two agree by construction, while the directory holding the file is up to
      # the publisher (`encore/database/` for `encore-database`,
      # `plugins/stitch-build/skills/react-components/` for `stitch::react-components`).
      # Path shape can therefore only ever be a hint about where to look — never proof
      # of what was found.
      #
      # Compared after parameterising, because a handful of publishers write a display
      # name where the spec wants a slug (`name: 'Database Sync'` for `database-sync`).
      # Rejecting those cost real descriptions for no safety gain: the parameterised
      # forms still have to match exactly, so someone else's skill cannot slip through.
      def matches_slug?(content, slug)
        published = name(content)
        return false if published.blank? || slug.blank?

        published == slug || published.parameterize == slug.to_s.parameterize
      end

      # A WEAKER match: the registry slug is this skill's published name carrying a
      # publisher's prefix. `vercel-labs/json-render` publishes `skills/react/SKILL.md`
      # with `name: react`, and skills.sh lists it as `json-render-react`.
      #
      # Only ever a fallback, and only inside a repository already narrowed to a
      # candidate path, because on its own it is ambiguous — `react` would answer to any
      # `*-react`. Callers must prefer #matches_slug? and reach for this only when
      # nothing in the repository identified itself exactly.
      def prefixed_slug?(content, slug)
        published = name(content)&.parameterize
        return false if published.blank? || slug.blank?

        slug.to_s.parameterize.end_with?("-#{published}")
      end

      private

      def normalize(content)
        content.to_s.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF").lstrip
      end

      def extract_frontmatter(content)
        content = normalize(content)
        return nil unless content.start_with?("---")

        parts = content.split(/^---\s*$/, 3)
        return nil if parts.length < 3

        parts[1]
      end

      def safe_yaml(raw)
        return nil if raw.blank?

        YAML.safe_load(raw)
      rescue Psych::Exception
        nil
      end

      def name_errors(name)
        return [ "name is required in frontmatter" ] if name.blank?

        errors = []
        errors << "name must be at most #{MAX_NAME_LENGTH} characters" if name.length > MAX_NAME_LENGTH
        unless name.match?(NAME_FORMAT)
          errors << "name must use lowercase letters, numbers and single hyphens, " \
                    "without leading or trailing hyphens"
        end
        errors
      end

      def description_errors(description)
        return [ "description is required in frontmatter — it tells the agent when to use the skill" ] if description.blank?
        return [ "description must be at most #{MAX_DESCRIPTION_LENGTH} characters" ] if description.length > MAX_DESCRIPTION_LENGTH

        []
      end

      def body_errors(body)
        return [ "SKILL.md needs instructions below the frontmatter" ] if body.blank?

        errors = []
        errors << "SKILL.md body should stay under #{MAX_BODY_LINES} lines" if body.lines.size > MAX_BODY_LINES
        errors << "SKILL.md body is too large (limit #{MAX_BODY_BYTES} bytes)" if body.bytesize > MAX_BODY_BYTES
        errors
      end
    end
  end
end
