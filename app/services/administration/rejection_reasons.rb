module Administration
  class RejectionReasons
    def initialize(actor)
      @actor = actor
    end

    def records
      permit!("read.candidate")
      RejectionReason.all
    end

    def create(attributes)
      permit!("manage.rejection_reason")
      persist("created") { RejectionReason.create!(attributes) }
    end

    def update(id, attributes)
      permit!("manage.rejection_reason")
      persist("updated") do
        reason = RejectionReason.lock.find(id)
        reason.update!(attributes)
        reason
      end
    end

    private

    def persist(action)
      RejectionReason.transaction do
        reason = yield
        AuditEvent.record!(actor: @actor, action: "rejection_reason.#{action}",
          subject: reason, changeset: reason.saved_changes)
        reason
      end
    end

    def permit!(permission)
      raise Recruitment::Planning::Forbidden unless @actor.allows?(permission)
    end
  end
end
