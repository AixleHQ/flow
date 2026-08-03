# frozen_string_literal: true

# Two facts a skill row could not previously carry.
#
# `origin` is the discriminator every behavioural difference keys off: whether the
# skills CLI can reinstall it, whether it has a registry URL, whether upstream can
# be checked for updates. Until now `source`/`package` presence was doing that job
# implicitly, which is why a hand-written skill had nowhere to live.
#
# `content_hash` is the registry's own digest, handed over by
# GET /api/download/<owner>/<repo>/<skill> alongside the files. It is free at
# install time and it is the only cheap way to answer "has upstream changed since
# we installed this" — the registry publishes no per-skill timestamp.
class AddOriginAndContentHashToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :origin, :string, default: "registry", null: false
    add_column :skills, :content_hash, :string
    add_index :skills, :origin
  end
end
