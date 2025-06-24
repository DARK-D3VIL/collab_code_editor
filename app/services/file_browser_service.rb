class FileBrowserService
  EXCLUDED = %w[. .. .git].freeze

  def initialize(repo_path)
    @repo_path = Pathname.new(repo_path)
  end

  def list_entries
    return [] unless File.directory?(@repo_path)

    Dir.entries(@repo_path)
       .reject { |e| EXCLUDED.include?(e) || e.end_with?(".unsaved") }
       .sort
  rescue => e
    Rails.logger.error("FileBrowser error: #{e.message}")
    []
  end
end
