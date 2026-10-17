module Web
  module ApplicationHelper
    NAVIGATION = [
      [ "Кандидаты", :candidates_path, "read.candidate", %w[candidates candidate_resumes] ],
      [ "Заявки на подбор", :job_requisitions_path, "read.job_requisition", %w[job_requisitions] ],
      [ "Кампании", :recruitment_campaigns_path, "read.recruitment_campaign", %w[recruitment_campaigns] ],
      [ "Шаблоны вакансий", :vacancy_templates_path, "read.vacancy_template", %w[vacancy_templates] ],
      [ "Сотрудники", :users_path, "manage.users", %w[users] ],
      [ "Роли и доступ", :roles_path, "manage.roles", %w[roles] ],
      [ "Справочники", :branches_path, "read.organization", %w[branches departments legal_entities] ],
      [ "Причины отказа", :rejection_reasons_path, "read.candidate", %w[rejection_reasons] ]
    ].freeze

    def workspace_navigation
      NAVIGATION.filter_map do |label, route, permission, controllers|
        next unless allowed?(permission)

        { label: label, path: public_send(route), active: controllers.include?(controller_name) }
      end
    end

    def allowed?(permission)
      current_user&.allows?(permission) || false
    end
  end
end
