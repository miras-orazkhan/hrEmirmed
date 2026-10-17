module Administration
  class Users
    def initialize(actor)
      @actor = actor
    end

    def save!(user, attributes)
      authorize!
      User.transaction do
        user.lock! if user.persisted?
        values = attributes.to_h.symbolize_keys
        current_role = user.role_id.present? ? Role.find(user.role_id) : nil
        target_role = values[:role_id].present? ? Role.find(values[:role_id]) : current_role
        [current_role, target_role].compact.uniq(&:id).sort_by(&:id).each(&:lock!)
        if !@actor.admin? && (current_role&.admin? || target_role&.admin?)
          raise Recruitment::Planning::Forbidden
        end
        blank_password = user.persisted? && values[:password].blank?
        values.delete(:password) if blank_password
        values.delete(:password_confirmation) if blank_password
        before_departments = user.department_ids
        user.update!(values)
        changes = user.saved_changes.merge("department_ids" => [before_departments, user.department_ids])
        AuditEvent.record!(actor: @actor, action: "user.saved", subject: user, changeset: changes)
      end
      user
    end

    private

    def authorize!
      raise Recruitment::Planning::Forbidden unless @actor&.allows?("manage.users")
    end
  end
end
