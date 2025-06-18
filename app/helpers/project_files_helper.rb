module ProjectFilesHelper
  def language_for_extension(file_name)
    ext = File.extname(file_name).delete(".").downcase
    base = File.basename(file_name)

    return "ruby" if %w[Gemfile Rakefile Guardfile Capfile config.ru].include?(base)
    return "dockerfile" if base == "Dockerfile"
    return "makefile" if base == "Makefile"

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
    }[ext] || "plaintext"
  end

  def editable_file?(file_name)
    non_editable_extensions = %w[
      ipynb pdf zip rar 7z tar gz bz2 xz
      exe dll bin class jar so o a
      png jpg jpeg gif bmp svg webp ico
      mp4 mkv avi mov wmv flv
      mp3 wav ogg flac
      ppt pptx xls xlsx doc docx
      iso dmg h5
    ]

    ext = File.extname(file_name).delete(".").downcase
    !non_editable_extensions.include?(ext)
  end

  def get_language_icon(language)
    return 'fas fa-file-code' if language.blank?
    
    icons = {
      'javascript' => 'fab fa-js-square',
      'typescript' => 'fab fa-js-square',
      'python' => 'fab fa-python',
      'ruby' => 'fas fa-gem',
      'java' => 'fab fa-java',
      'php' => 'fab fa-php',
      'html' => 'fab fa-html5',
      'css' => 'fab fa-css3-alt',
      'scss' => 'fab fa-sass',
      'go' => 'fab fa-golang',
      'rust' => 'fab fa-rust',
      'swift' => 'fab fa-swift',
      'csharp' => 'fab fa-microsoft',
      'sql' => 'fas fa-database',
      'json' => 'fas fa-brackets-curly',
      'markdown' => 'fab fa-markdown',
      'yaml' => 'fas fa-file-lines',
      'docker' => 'fab fa-docker',
      'bash' => 'fas fa-terminal',
      'erb' => 'fas fa-gem'
    }
    
    clean_language = language.to_s.downcase.strip
    icons[clean_language] || 'fas fa-file-code'
  end
end
