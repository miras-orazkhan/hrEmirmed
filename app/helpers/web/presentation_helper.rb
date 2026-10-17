module Web
  module PresentationHelper
    LABELS = {
      "draft" => "Черновик", "approved" => "Утверждён", "ready" => "Готова к запуску",
      "recruiting" => "Идёт подбор", "paused" => "Приостановлено", "closed" => "Закрыта",
      "cancelled" => "Отменено", "pending_approval" => "Ожидает запуска", "active" => "Активно",
      "completed" => "Завершено", "screening" => "Первичный отбор", "test_review" => "Проверка теста",
      "interview" => "Собеседование", "internship" => "Стажировка", "offer" => "Предложение",
      "rejected" => "Отказ компании", "withdrawn" => "Отказ кандидата", "onsite" => "Очно", "online" => "Онлайн"
    }.freeze

    def state_label(value)
      LABELS.fetch(value.to_s, value.presence || "—")
    end

    def state_badge(value)
      tag.span(state_label(value), class: "status status--#{value.to_s.parameterize}")
    end

    def form_value(scope, field, fallback = nil)
      payload = params[scope]
      payload.is_a?(ActionController::Parameters) && payload.key?(field) ? payload[field] : fallback
    end

    def editable_candidate?(candidate)
      Candidates::Access.new(current_user).authorize_update!(candidate)
      true
    rescue Recruitment::Planning::Forbidden, Recruitment::Planning::InvalidTransition
      false
    end

    def manages_requisition?(record)
      allowed?("manage.job_requisition") && (current_user.admin? || record.recruiter_id == current_user.id)
    end

    def edits_requisition?(record)
      allowed?("update.job_requisition") && !%w[closed cancelled].include?(record.status) &&
        (current_user.admin? || current_user.department_ids.include?(record.department_id))
    end

    def decides_application?(application)
      request = application.job_requisition
      return false unless application.status == "active" && request.status == "recruiting" && request.recruitment_campaign.status == "active"
      permission, assignee = case application.stage
      when "interview" then [ "conduct.interview", application.job_requisition_version.interviewer_id ]
      when "internship" then [ "supervise.internship", application.job_requisition_version.internship_supervisor_id ]
      else [ "manage.candidate_application", request.recruiter_id ]
      end
      allowed?(permission) && (current_user.admin? || current_user.id == assignee)
    end

    def date_label(value)
      value ? value.strftime("%d.%m.%Y") : "—"
    end
  end
end
