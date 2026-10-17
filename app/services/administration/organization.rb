module Administration
  class Organization
    RESOURCES = {
      "branches" => Branch,
      "departments" => Department,
      "legal_entities" => LegalEntity
    }.freeze

    def initialize(actor, resource_name)
      @actor = actor
      @resource_class = RESOURCES.fetch(resource_name.to_s)
    end

    def records
      permit!("read.organization")
      return @resource_class.all if @actor.allows?("manage.organization")

      case @resource_class.name
      when "Branch" then Branch.where(id: @actor.branch_id)
      when "Department" then @actor.departments
      when "LegalEntity" then LegalEntity.all
      end
    end

    def create(attributes)
      persist(@resource_class.new(attributes), "created")
    end

    def update(id, attributes)
      record = @resource_class.find(id)
      record.assign_attributes(attributes)
      persist(record, "updated")
    end

    private

    def persist(record, action)
      permit!("manage.organization")
      record.class.transaction do
        record.save!
        AuditEvent.record!(actor: @actor,
          action: "#{record.model_name.singular}.#{action}", subject: record,
          changeset: record.saved_changes)
      end
      record
    end

    def permit!(permission)
      raise Recruitment::Planning::Forbidden unless @actor.allows?(permission)
    end
  end
end
