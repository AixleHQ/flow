# frozen_string_literal: true

module Templates
  # The templates repository's namespaces.yaml: who publishes under which name.
  #
  #   - name: acme                # the namespace in templates/<name>/<slug>/
  #     display_name: Acme Corp
  #     url: https://acme.example
  #     verified: false           # set by the Flow maintainers only
  #     owners: [acme-bot, jdoe]  # GitHub logins allowed to change its templates
  #
  # Parsed by the catalog sync (to show publishers) and by the repository's CI
  # (to check that a pull request's author owns the namespaces it touches).
  class NamespaceRegistry
    FILE = "namespaces.yaml"
    GITHUB_LOGIN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\z/

    Entry = Struct.new(:name, :display_name, :url, :verified, :owners, keyword_init: true)

    attr_reader :entries, :errors

    def self.parse(yaml) = new(yaml)

    def initialize(yaml)
      @errors = []
      @entries = {}
      load(yaml)
    end

    def [](name) = @entries[name.to_s]

    def names = @entries.keys

    def owner?(name, login)
      entry = self[name]
      entry.present? && entry.owners.map(&:downcase).include?(login.to_s.downcase)
    end

    private

    def load(yaml)
      raw = yaml.present? ? YAML.safe_load(yaml.dup.force_encoding(Encoding::UTF_8), permitted_classes: [], aliases: false) : []
      return @errors << "#{FILE} must be a list" unless raw.is_a?(Array)

      raw.each_with_index { |item, index| add(item, index) }
    rescue Psych::Exception => e
      @errors << "#{FILE}: #{e.message}"
    end

    def add(item, index)
      label = "#{FILE}[#{index}]"
      return @errors << "#{label} must be a mapping" unless item.is_a?(Hash)

      name = item["name"].to_s
      owners = Array(item["owners"]).map(&:to_s)
      problems = []
      problems << "name #{name.inspect} must be lowercase words joined by dashes" unless name.match?(Package::NAME_FORMAT)
      problems << "#{name} is listed twice" if @entries.key?(name)
      problems << "#{name} needs at least one owner" if owners.empty?
      owners.reject { |login| login.match?(GITHUB_LOGIN) }.each { |login| problems << "#{name}: #{login.inspect} is not a GitHub login" }
      return @errors.concat(problems.map { |p| "#{label}: #{p}" }) if problems.any?

      @entries[name] = Entry.new(name: name, display_name: item["display_name"].presence || name,
                                 url: item["url"].presence, verified: item["verified"] == true, owners: owners)
    end
  end
end
