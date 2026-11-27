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

  def warnings_for(target, instructions)
    path = target.join("template.yaml")
    path.write(path.read.sub("instructions: Implement the design and open a pull request.", "instructions: #{instructions.inspect}"))
    Templates::RepositoryValidator.new(root: @root).warnings
  end

  test "a step that names a platform tool it does not list gets a warning" do
    target = checkout(@root)

    warnings = warnings_for(target, "Implement it, then call board_move_task.")

    assert_equal [ "workflow delivery step implement names board_move_task but does not list it in tools" ],
                 warnings["acme/dev-team-sdlc"]
    assert_empty validate, "a warning is not an error"
  end

  test "a step that names only the tools it lists gets no warning" do
    target = checkout(@root)

    assert_empty warnings_for(target, "Implement it, then call run_tests.")
    assert_empty Templates::RepositoryValidator.new(root: @root).warnings
  end

  test "a {{tool:key}} reference to an unlisted tool gets a warning" do
    target = checkout(@root)

    warnings = warnings_for(target, "Use {{tool:board_comment}} to report.")

    assert_equal [ "workflow delivery step implement names board_add_comment but does not list it in tools" ],
                 warnings["acme/dev-team-sdlc"]
  end

  test "a mixed-case {{tool:KEY}} reference to an unlisted tool gets a warning" do
    target = checkout(@root)

    warnings = warnings_for(target, "Use {{TOOL:Board_Comment}} to report.")

    assert_equal [ "workflow delivery step implement names board_add_comment but does not list it in tools" ],
                 warnings["acme/dev-team-sdlc"]
  end

  test "a tool named only in an agent's communication_style gets a warning" do
    target = checkout(@root)
    path = target.join("template.yaml")
    path.write(path.read.sub("    persona: Designs systems and writes clear notes.\n",
                             "    persona: Designs systems and writes clear notes.\n    communication_style: Always finish by calling board_move_task.\n"))

    warnings = Templates::RepositoryValidator.new(root: @root).warnings

    assert_includes warnings["acme/dev-team-sdlc"],
                    "workflow delivery step implement names board_move_task but does not list it in tools"
  end

  test "warnings skip a directory without template.yaml and call still reports it" do
    checkout(@root).join("template.yaml").delete

    validator = Templates::RepositoryValidator.new(root: @root)

    assert_empty validator.warnings
    assert_includes validator.call["acme/dev-team-sdlc"], "template.yaml is missing"
  end

  test "warnings skip a schema-invalid package and call still reports it" do
    target = checkout(@root)
    path = target.join("template.yaml")
    path.write(path.read.sub("instructions: Implement the design and open a pull request.",
                             "instructions: Call board_move_task.\n        depends_on: [missing_step]"))

    validator = Templates::RepositoryValidator.new(root: @root)

    assert_empty validator.warnings
    assert_not_empty validator.call["acme/dev-team-sdlc"]
  end
end
