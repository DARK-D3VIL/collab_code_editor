module GithubHelper
  def sidebar_link_class(name)
    current_action = action_name
    "nav-link #{"active fw-bold text-primary" if current_action == name}"
  end
end
