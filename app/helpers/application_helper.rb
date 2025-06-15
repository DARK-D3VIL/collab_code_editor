module ApplicationHelper
  def github_token_valid?
    current_user&.github_token_valid?
  end
end
