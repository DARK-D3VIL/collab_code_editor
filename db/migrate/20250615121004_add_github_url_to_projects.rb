class AddGithubUrlToProjects < ActiveRecord::Migration[7.2]
  def change
    add_column :projects, :github_url, :string
  end
end
