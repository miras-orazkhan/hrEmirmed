module Administration
  class Roles
    def initialize(actor)
      @actor = actor
    end

    def save!(role, attributes)
      raise Recruitment::Planning::Forbidden unless @actor&.allows?("manage.roles")

      Role.transaction do
        role.lock! if role.persisted?
        values = attributes.to_h.symbolize_keys
        if !@actor.admin? && (role.admin? || values[:name] == "admin")
          raise Recruitment::Planning::Forbidden
        end
        role.update!(values)
        AuditEvent.record!(actor: @actor, action: "role.saved", subject: role, changeset: role.saved_changes)
      end
      role
    end
  end
end
