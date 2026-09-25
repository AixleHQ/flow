# frozen_string_literal: true

namespace :encryption do
  desc "Re-encrypt every stored secret under the current keys (bound to its model and column once " \
       "encryption.bind_purpose is on) — the last step of a key rotation. Lists, by id, every row no configured " \
       "key can read. DRY_RUN=true only reads and lists."
  task reencrypt: :environment do
    dry_run = ENV["DRY_RUN"] == "true"
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.select { |model| model.include?(Encryptable) && model.encrypted_columns.any? }

    models.sort_by(&:name).each do |model|
      done = 0
      unreadable = []
      model.unscoped.find_each do |record|
        if dry_run
          done += 1 if record.read_secrets!
        elsif record.reencrypt_secrets!
          done += 1
        end
      rescue Encryptable::DecryptionError
        unreadable << record.id
      end
      puts "[encryption:reencrypt] #{model.name}: #{done} #{dry_run ? 'readable' : 'rewritten'}, " \
           "#{unreadable.size} unreadable#{" (ids: #{unreadable.join(', ')})" if unreadable.any?}"
    end
  end
end
