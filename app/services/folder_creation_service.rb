class FolderCreationService
  Result = Struct.new(:success?, :error)

  def initialize(base_path, folder_name)
    @base_path = Pathname.new(base_path)
    @folder_name = folder_name
  end

  def call
    raise "Invalid folder name" if @folder_name.blank?

    new_folder = @base_path.join(@folder_name)
    FileUtils.mkdir_p(new_folder)

    Result.new(true, nil)
  rescue => e
    Result.new(false, e.message)
  end
end
