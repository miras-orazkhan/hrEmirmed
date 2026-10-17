module Web
  module WorkflowsHelper
    PAGE_SIZE = 50

    def workflow_page(scope, cursor: params[:cursor])
      value = cursor.to_s
      unless value.empty? || (value.match?(/\A[0-9]{1,19}\z/) && value.to_i.between?(1, 9_223_372_036_854_775_807))
        raise ActionController::ParameterMissing, :cursor
      end

      scope = scope.where(scope.klass.arel_table[:id].gt(value.to_i)) if value.present?
      rows = scope.reorder(id: :asc).limit(PAGE_SIZE + 1).to_a
      if rows.size > PAGE_SIZE
        rows.pop
        @next_cursor = rows.last.id
      end
      rows
    end

    def lines_to_list(value)
      value.to_s.lines.map(&:strip).reject(&:blank?).uniq
    end

    def validation_messages(record)
      record.errors.attribute_names.map do |field|
        labels = { name: "Название", login: "Логин", password: "Пароль",
          password_confirmation: "Подтверждение пароля", role: "Роль", permissions: "Права доступа",
          branch: "Филиал", departments: "Подразделения", registration_number: "Регистрационный номер",
          full_name: "ФИО", title: "Название", duties: "Обязанности", value: "Контакт",
          recruiter: "Рекрутер", interviewer: "Интервьюер", internship_supervisor: "Руководитель стажировки",
          salary_amount: "Зарплата", work_schedule: "График", desired_start_on: "Дата выхода",
          positions_count: "Количество мест", internship_duration: "Длительность стажировки",
          internship_criteria: "Критерии стажировки", search_query: "Поисковый запрос" }
        "#{labels.fetch(field, 'Данные формы')}: проверьте заполнение и допустимость значения."
      end.uniq
    end

    def form_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def workflow_error_message(error)
      reason = error.message
      messages = {
        "template_must_be_approved" => "Сначала утвердите шаблон вакансии.",
        "campaign_already_active" => "Кампания уже запущена.",
        "no_ready_requisitions" => "В кампании нет готовых заявок для запуска.",
        "requisition_cannot_pause" => "Эту заявку нельзя приостановить.",
        "requisition_cannot_resume" => "Эту заявку нельзя возобновить.",
        "requisition_cannot_cancel" => "Эту заявку нельзя отменить.",
        "next_application_decision_required" => "Укажите, разрешён ли следующий подбор кандидата.",
        "candidate_has_active_application" => "У кандидата уже есть активное рассмотрение.",
        "next_application_not_allowed" => "Для следующего подбора нужно отдельное разрешение.",
        "requisition_not_recruiting" => "Подбор по этой заявке сейчас не ведётся.",
        "employment_workflow_required" => "Следующий этап требует отдельного процесса оформления.",
        "rejection_reason_required" => "Выберите действующую причину отказа компании.",
        "unsupported_outcome" => "Выберите допустимое решение по кандидату.",
        "application_already_completed" => "Рассмотрение уже завершено.",
        "recruiter_transfer_requires_separate_workflow" => "Перенос рекрутера требует отдельного процесса."
      }
      messages.fetch(reason, "Не удалось выполнить действие. Проверьте данные и состояние записи.")
    end
  end
end
