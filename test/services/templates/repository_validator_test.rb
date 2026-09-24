# frozen_string_literal: true

require "test_helper"

class Templates::RepositoryValidatorTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")

  setup do
    @root = Pathname(Dir.mktmpdir)
    @base = Pathname(Dir.mktmpdir)
  end

  teardown do
    FileUtils.rm_rf([ @root, @base ])
  end

  def checkout(root, slug: "dev-team-sdlc")
    target = root.join("templates", slug)
    FileUtils.mkdir_p(target.dirname)
    FileUtils.cp_r(FIXTURE, target)
    target
  end

  test "a valid checkout has no errors" do
    checkout(@root)

    assert_empty Templates::RepositoryValidator.call(root: @root)
  end

  test "a template with requirements must explain them in SETUP.md" do
    checkout(@root).join("SETUP.md").delete

    errors = Templates::RepositoryValidator.call(root: @root)

    assert_includes errors["dev-team-sdlc"], "SETUP.md is required when the template has requirements"
  end

  test "a changed template must increase its version over the base branch" do
    checkout(@base)
    changed = checkout(@root)
    changed.join("README.md").write("# Dev team SDLC\n\nNow with more.\n")

    errors = Templates::RepositoryValidator.call(root: @root, base_root: @base)
    assert_match(/version is still 3/, errors["dev-team-sdlc"].join)

    changed.join("template.yaml").write(changed.join("template.yaml").read.sub("version: 3", "version: 4"))
    assert_empty Templates::RepositoryValidator.call(root: @root, base_root: @base)
  end

  test "the directory name must be the slug" do
    checkout(@root, slug: "renamed")

    assert_includes Templates::RepositoryValidator.call(root: @root)["renamed"],
                    'directory name does not match slug "dev-team-sdlc"'
  end
end
