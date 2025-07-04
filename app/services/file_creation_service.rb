class FileCreationService
  Result = Struct.new(:success?, :error) do
    def success?
      self[:success?]
    end
  end

  def initialize(project, params)
    @project = project
    @params = params
  end

  def call
    begin
      repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
      relative_path = Pathname.new(@params[:path].to_s).cleanpath.to_s
      filename = @params[:name].to_s.strip

      file_path = File.join(repo_path, relative_path, filename)

      # Ensure we are writing *inside* the project directory
      unless file_path.start_with?(repo_path.to_s)
        return Result.new(false, "Invalid path")
      end

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, @params[:content] || "")

      Result.new(true, nil)
    rescue => e
      Result.new(false, e.message)
    end
  end
end
