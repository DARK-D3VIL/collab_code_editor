module ApplicationHelper
  def github_token_valid?
    return false if current_user.github_token.blank?

    begin
      response = Faraday.get("https://api.github.com/user", {}, {
        Authorization: "token #{current_user.github_token}",
        Accept: "application/vnd.github+json"
      })

      response.status == 200
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      false
    end
  end
end
