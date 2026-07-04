# frozen_string_literal: true

# Rug-pull defense for user-authored custom tools: definition_digest pins the
# publisher-validated definition (serving re-verifies and fails closed on
# mismatch — any write bypassing CustomTools::Publisher makes the tool vanish
# from tools/list instead of serving tampered metadata). docker_image_digest
# pins the image at first execution so a mutable tag can't swap code silently.
class AddDigestsToTools < ActiveRecord::Migration[8.1]
  def change
    add_column :tools, :definition_digest, :string
    add_column :tools, :docker_image_digest, :string
  end
end
