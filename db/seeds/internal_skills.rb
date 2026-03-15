# frozen_string_literal: true

module Seeds
  module InternalSkills
    def self.seed!
      puts "Syncing internal skills..."

      Dir.glob(Rails.root.join("db/internal_skills/*.md")).sort.each do |file_path|
        name = File.basename(file_path, ".md")
        raw = File.read(file_path)

        title, description, content = if raw.start_with?("---")
          parts = raw.split("---", 3)
          meta = parts.length >= 3 ? (YAML.safe_load(parts[1]) || {}) : {}
          [ meta["title"], meta["description"], (parts[2] || "").strip ]
        else
          [ nil, nil, raw.strip ]
        end

        skill = Skill.find_or_initialize_by(name: name, kind: :internal)
        skill.assign_attributes(title: title, description: description, content: content)
        skill.save! if skill.new_record? || skill.changed?
        puts "  Internal skill: #{name} — #{title}"
      end
    end
  end
end
