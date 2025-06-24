module ConflictsHelper
  def format_conflict_lines(lines_changed)
    return "No lines" if lines_changed.blank?

    if lines_changed.is_a?(Array)
      lines_changed.join(", ")
    else
      lines_changed.to_s
    end
  end

  def conflict_severity_class(conflict)
    lines_count = conflict.lines_changed&.count || 0
    case lines_count
    when 0..2
      "border-warning"
    when 3..5
      "border-danger"
    else
      "border-dark"
    end
  end

  def truncate_code_content(content, length = 100)
    return "Empty" if content.blank?

    if content.length > length
      "#{content[0..length]}..."
    else
      content
    end
  end

  def conflict_age_class(conflict)
    age_in_minutes = (Time.current - conflict.created_at) / 1.minute

    case age_in_minutes
    when 0..2
      "text-danger"  # Very recent - urgent
    when 2..10
      "text-warning" # Recent - attention needed
    else
      "text-muted"   # Older
    end
  end
end
