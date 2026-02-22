# frozen_string_literal: true

namespace :palad do
  desc "Sync internal skills from db/internal_skills/*.md into the database"
  task sync_internal_skills: :environment do
    skills_dir = Rails.root.join("db", "internal_skills")

    unless skills_dir.exist?
      puts "No internal skills directory found at #{skills_dir}"
      next
    end

    files = Dir.glob(skills_dir.join("*.md")).sort
    if files.empty?
      puts "No .md files found in #{skills_dir}"
      next
    end

    synced = []
    files.each do |file_path|
      name = File.basename(file_path, ".md")
      raw = File.read(file_path)
      title, description, content = parse_front_matter(raw)

      skill = Skill.find_or_initialize_by(name: name, kind: :internal)
      skill.assign_attributes(title: title, description: description, content: content)

      if skill.new_record?
        skill.save!
        puts "  [created] #{name} — #{title}"
      elsif skill.changed?
        skill.save!
        puts "  [updated] #{name} — #{title}"
      else
        puts "  [unchanged] #{name}"
      end

      synced << name
    end

    # Remove internal skills that no longer have a file on disk
    removed = Skill.internal_skills.where.not(name: synced)
    if removed.any?
      removed.each { |s| puts "  [removed] #{s.name}" }
      removed.destroy_all
    end

    puts "Internal skills sync complete: #{synced.size} synced, #{removed.size rescue 0} removed"
  end
end

def parse_front_matter(raw)
  if raw.start_with?("---")
    parts = raw.split("---", 3)
    if parts.length >= 3
      meta = YAML.safe_load(parts[1]) || {}
      content = parts[2].strip
      return meta["title"], meta["description"], content
    end
  end

  [nil, nil, raw.strip]
end
