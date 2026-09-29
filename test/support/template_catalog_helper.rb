# frozen_string_literal: true

# A mirrored catalog entry built from a fixture package, the way
# Templates::CatalogSync would store it.
module TemplateCatalogHelper
  TEMPLATE_FIXTURES = Rails.root.join("test/fixtures/files/templates")

  def create_catalog_template(fixture = "dev-team-sdlc", commit_sha: SecureRandom.hex(20))
    package = Templates::Package.from_directory(TEMPLATE_FIXTURES.join(fixture))
    CatalogTemplate.new.assign_package(package, commit_sha: commit_sha).tap(&:save!)
  end
end

ActiveSupport::TestCase.include(TemplateCatalogHelper)
ActionDispatch::IntegrationTest.include(TemplateCatalogHelper)
