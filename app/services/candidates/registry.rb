module Candidates
  class Registry
    FIELDS = %w[full_name preferred_language city summary].freeze

    def initialize(actor)
      @actor = actor
    end

    def create(attributes, permission: "create.candidate")
      permit!(permission)
      attributes = attributes.stringify_keys
      Candidate.transaction do
        lock_contacts!(attributes.fetch("contacts", []))
        owner_id = attributes["responsible_recruiter_id"].presence || @actor.id
        raise Recruitment::Planning::Forbidden if owner_id.to_s != @actor.id.to_s && !@actor.admin?
        candidate = Candidate.create!(attributes.slice(*FIELDS).merge(created_by: @actor, responsible_recruiter_id: owner_id))
        write_contacts!(candidate, attributes.fetch("contacts", []))
        sources = attributes.fetch("sources", [])
        validate_list!(sources, :sources)
        sources.each { |source| candidate.sources.create!(source.stringify_keys.slice("provider", "external_id")) }
        Duplicates.detect!(candidate)
        audit!(candidate, "candidate.created")
        candidate
      end
    end

    def update(id, attributes)
      attributes = attributes.stringify_keys
      Candidate.transaction do
        lock_contacts!(attributes.fetch("contacts", []))
        candidate = Access.new(@actor).visible_candidates.lock("FOR NO KEY UPDATE").find(id)
        Access.new(@actor).authorize_update!(candidate)
        candidate.update!(attributes.slice(*FIELDS))
        if attributes.key?("contacts")
          CandidateContact.where(candidate_id: candidate.id).delete_all
          candidate.association(:contacts).reset
          write_contacts!(candidate, attributes["contacts"])
        end
        Duplicates.detect!(candidate)
        audit!(candidate, "candidate.updated")
        candidate
      end
    end

    private

    def permit!(permission)
      raise Recruitment::Planning::Forbidden unless @actor.allows?(permission)
    end

    def validate_list!(items, field)
      unless items.is_a?(Array) && items.size <= 20 && items.all? { |item| item.respond_to?(:stringify_keys) }
        raise ActionController::ParameterMissing, field
      end
    end

    def lock_contacts!(contacts)
      validate_list!(contacts, :contacts)
      keys = contacts.map do |contact|
        contact = contact.stringify_keys
        "#{contact['kind']}:#{CandidateContact.normalize(contact['kind'], contact['value'])}"
      end.uniq.sort
      keys.each do |key|
        # Serialize simultaneous matching contact writes without a global lock.
        digest = Digest::SHA256.hexdigest(key)[0, 15].to_i(16)
        Candidate.connection.execute("SELECT pg_advisory_xact_lock(#{digest})")
      end
    end

    def write_contacts!(candidate, contacts)
      contacts.each { |contact| candidate.contacts.create!(contact.stringify_keys.slice("kind", "value")) }
    end

    def audit!(candidate, action)
      AuditEvent.record!(actor: @actor, action: action, subject: candidate,
        changeset: { "responsible_recruiter_id" => candidate.responsible_recruiter_id })
    end
  end
end
