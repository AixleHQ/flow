class AddPreferredArtifactsLanguageToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :preferred_artifacts_language, :string, default: "en"
  end
end
