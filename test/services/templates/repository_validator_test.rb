# frozen_string_literal: true

require "test_helper"

class Templates::RepositoryValidatorTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")
  NAMESPACES = "- { name: acme, display_name: Acme Corp, owners: [acme-bot] }\n"

  setup do
    @root = Pathname(Dir.mktmpdir)
    @base = Pathname(Dir.mktmpdir)
  end

  teardown do
    FileUtils.rm_rf([ @root, @base ])
  end

  def checkout(root, namespaces: NAMESPACES, slug: "dev-team-sdlc")
    root.join("namespaces.yaml").write(namespaces)
    target = root.join("templates", "acme", slug)
    FileUtils.mkdir_p(target.dirname)
    FileUtils.cp_r(FIXTURE, target)
    target
  end

  def validate(**options) = Templates::RepositoryValidator.call(root: @root, **options)

  test "a valid checkout has no errors" do
    checkout(@root)

    assert_empty validate
  end

  test "a template under an unregistered namespace is refused" do
    checkout(@root, namespaces: "[]")

    assert_includes validate["acme/dev-team-sdlc"], "namespace acme is not registered in namespaces.yaml"
  end

  test "the directory must be namespace/slug" do
    checkout(@root, slug: "renamed")

    assert_includes validate["acme/renamed"], 'directory does not match namespace/slug "acme/dev-team-sdlc"'
  end

  test "a template outside any namespace is pointed at the new layout" do
    checkout(@root)
    FileUtils.cp_r(FIXTURE, @root.join("templates/loose"))

    assert(validate["namespaces.yaml"].any? { |e| e.include?("templates/loose is a template outside a namespace") })
  end

  test "a template with requirements must explain them in SETUP.md" do
    checkout(@root).join("SETUP.md").delete

    assert_includes validate["acme/dev-team-sdlc"], "SETUP.md is required when the template has requirements"
  end

  test "a changed template must increase its version over the base branch" do
    checkout(@base)
    changed = checkout(@root)
    changed.join("README.md").write("# Dev team SDLC\n\nNow with more.\n")

    assert_match(/version is still 3/, validate(base_root: @base)["acme/dev-team-sdlc"].join)

    changed.join("template.yaml").write(changed.join("template.yaml").read.sub("version: 3", "version: 4"))
    assert_empty validate(base_root: @base)
  end

  test "only an owner of the namespace may change its templates" do
    checkout(@base)
    changed = checkout(@root)
    changed.join("template.yaml").write(changed.join("template.yaml").read.sub("version: 3", "version: 4"))

    assert_empty validate(base_root: @base, author: "acme-bot")
    assert_includes validate(base_root: @base, author: "mallory")["acme/dev-team-sdlc"],
                    "mallory is not an owner of the acme namespace (namespaces.yaml)"
    assert_empty validate(base_root: @base, author: "mallory", author_is_maintainer: true)
  end

  test "a pull request cannot make its author an owner of an existing namespace" do
    checkout(@base)
    changed = checkout(@root, namespaces: "- { name: acme, owners: [acme-bot, mallory] }\n")
    changed.join("template.yaml").write(changed.join("template.yaml").read.sub("version: 3", "version: 4"))

    assert_includes validate(base_root: @base, author: "mallory")["acme/dev-team-sdlc"],
                    "mallory is not an owner of the acme namespace (namespaces.yaml)"
  end

  test "a new namespace is owned by whoever the pull request lists" do
    @base.join("namespaces.yaml").write("[]")
    checkout(@root)

    assert_empty validate(base_root: @base, author: "acme-bot")
  end

  test "an unchanged template needs no ownership" do
    checkout(@base)
    checkout(@root)

    assert_empty validate(base_root: @base, author: "someone-else")
  end
end
