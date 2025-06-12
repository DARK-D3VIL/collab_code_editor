module ProjectFilesHelper
  def language_for_extension(file_extension)
    {
      "rb" => "ruby",
      "js" => "javascript",
      "ts" => "typescript",
      "jsx" => "javascript",
      "tsx" => "typescript",
      "html" => "html",
      "htm" => "html",
      "css" => "css",
      "scss" => "scss",
      "less" => "less",
      "json" => "json",
      "yaml" => "yaml",
      "yml" => "yaml",
      "xml" => "xml",
      "md" => "markdown",
      "markdown" => "markdown",
      "py" => "python",
      "java" => "java",
      "c" => "c",
      "cpp" => "cpp",
      "h" => "cpp",
      "cs" => "csharp",
      "go" => "go",
      "php" => "php",
      "sh" => "shell",
      "sql" => "sql",
      "swift" => "swift",
      "txt" => "plaintext",
      "rs" => "rust",
      "dart" => "dart",
      "scala" => "scala",
      "lua" => "lua",
      "r" => "r",
      "ini" => "ini",
      "toml" => "toml",
      "cfg" => "ini",
      "dockerfile" => "dockerfile",
      "makefile" => "makefile"
    }[file_extension.to_s.downcase] || "plaintext"
  end

  def editable_file?(file_name)
    editable_extensions = %w[
      rb js ts jsx tsx html htm css scss less json yaml yml xml md markdown
      py java c cpp h cs go php sh sql swift txt rs dart scala lua r ini toml cfg
      dockerfile makefile
    ]

    ext = File.extname(file_name).delete(".").downcase
    editable_extensions.include?(ext)
  end
end
