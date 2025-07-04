module ProjectGitHelper
  def sidebar_link_class(name, controllername)
    current_action = action_name
    current_controller = controller_name
    "nav-link #{"active fw-bold text-primary" if current_action == name && current_controller == controllername}"
  end

  def current_branch_id
    return unless defined?(@project) && @project.present?
    membership = current_user.project_memberships.find_by(project_id: @project.id)
    membership&.current_branch_id || @project.branches.find_by(name: "main")&.id
  end

  def format_diff(patch)
    return content_tag(:span, "No diff available", class: "line info") if patch.nil?

    lines = patch.split("\n")
    lines.map do |line|
      css_class =
        if line.start_with?("+") && !line.start_with?("+++")
          "add"
        elsif line.start_with?("-") && !line.start_with?("---")
          "del"
        elsif line.start_with?("@@") || line.start_with?("diff") || line.start_with?("index")
          "info"
        else
          "normal"
        end

      content_tag(:span, line, class: "line #{css_class}")
    end.join.html_safe
  end

  def safe_encode_diff(diff_content)
    return "" if diff_content.nil?
    diff_content.to_s.encode("UTF-8",
      invalid: :replace,
      undef: :replace,
      replace: "�"
    )
  end
end
