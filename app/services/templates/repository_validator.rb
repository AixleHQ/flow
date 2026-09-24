# frozen_string_literal: true

module Templates
  # The templates repository's CI gate (design §6.3), run against a checkout:
  #
  #   bin/rails templates:validate ROOT=path/to/flow-templates [BASE=path/to/base-checkout]
  #
  # The same Templates::Validator every installation runs, plus the rules that
  # only make sense for the repository: the directory name is the slug, a
  # template that asks for setup explains it in SETUP.md, and a changed template
  # has a higher version than on the base branch.
  class RepositoryValidator
    def self.call(...) = new(...).call

    def initialize(root:, base_root: nil)
      @root = Pathname(root)
      @base_root = base_root && Pathname(base_root)
    end

    # @return [Hash{String => Array<String>}] slug → errors, only for templates with errors
    def call
      template_dirs(@root).each_with_object({}) do |dir, errors|
        problems = check(dir)
        errors[dir.basename.to_s] = problems if problems.any?
      end
    end

    private

    def template_dirs(root)
      root.join(CatalogSync::TEMPLATES_DIR).children.select(&:directory?).sort
    end

    def check(dir)
      return [ "#{Package::DEFINITION_FILE} is missing" ] unless dir.join(Package::DEFINITION_FILE).file?

      package = Package.from_directory(dir)
      errors = Validator.new(package).errors
      errors << "directory name does not match slug #{package.slug.inspect}" if package.slug != dir.basename.to_s
      errors << "#{Package::SETUP_FILE} is required when the template has requirements" if needs_setup?(package)
      errors << "#{Package::README_FILE} is missing" if package.readme.blank?
      errors.concat(version_errors(package, dir.basename.to_s))
      errors
    rescue Psych::Exception => e
      [ "#{Package::DEFINITION_FILE}: #{e.message}" ]
    end

    def needs_setup?(package)
      requirements = package.requires.values_at("integrations", "repositories", "secrets").flatten.compact
      requirements.any? && package.setup_markdown.blank?
    end

    def version_errors(package, slug)
      base_dir = @base_root&.join(CatalogSync::TEMPLATES_DIR, slug)
      return [] unless base_dir&.join(Package::DEFINITION_FILE)&.file?

      base = Package.from_directory(base_dir)
      return [] if base.digest == package.digest || package.version.to_i > base.version.to_i

      [ "changed since the base branch but version is still #{package.version} — increase it" ]
    rescue Psych::Exception
      []
    end
  end
end
