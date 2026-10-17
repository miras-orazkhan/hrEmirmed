module Candidates
  class Duplicates
    INSERT_BATCH_SIZE = 500

    def initialize(actor)
      @actor = actor
    end

    def visible
      raise Recruitment::Planning::Forbidden unless @actor.allows?("resolve.candidate_duplicate")
      scope = CandidateDuplicate.includes(:candidate, :other_candidate)
      return scope if @actor.allows?("manage.all_candidate_duplicates")
      owned = Candidate.where(responsible_recruiter_id: @actor.id).select(:id)
      scope.where(candidate_id: owned, other_candidate_id: owned)
    end

    def resolve(id, attributes)
      CandidateDuplicate.transaction do
        candidate_ids = CandidateDuplicate.where(id: id).pick(:candidate_id, :other_candidate_id)
        raise ActiveRecord::RecordNotFound unless candidate_ids
        Candidate.where(id: candidate_ids).order(:id).lock("FOR NO KEY UPDATE").load
        duplicate = visible.lock.find(id)
        raise Recruitment::Planning::InvalidTransition, "duplicate_already_resolved" unless duplicate.status == "pending"
        status = attributes["status"]
        raise ActionController::ParameterMissing, :status unless %w[distinct confirmed].include?(status)
        duplicate.update!(status: status, resolved_by: @actor, resolved_at: Time.current,
          resolution_note: attributes["resolution_note"])
        AuditEvent.record!(actor: @actor, action: "candidate_duplicate.resolved", subject: duplicate,
          changeset: duplicate.saved_changes)
        duplicate
      end
    end

    # Exact normalized contacts suggest a possible duplicate, never an automatic merge.
    def self.detect!(candidate)
      matching_candidates = CandidateContact.where(
        "(candidate_contacts.kind, candidate_contacts.normalized_value) IN " \
        "(SELECT kind, normalized_value FROM candidate_contacts WHERE candidate_id = ?)", candidate.id)
        .where.not(candidate_id: candidate.id).group(:candidate_id)

      last_id = nil
      loop do
        batch = matching_candidates
        batch = batch.where("candidate_contacts.candidate_id > ?", last_id) if last_id
        other_ids = batch.order(:candidate_id).limit(INSERT_BATCH_SIZE).pluck(:candidate_id)
        break if other_ids.empty?

        pairs = other_ids.map do |other_id|
          first, second = [ candidate.id, other_id ].sort
          { candidate_id: first, other_candidate_id: second }
        end
        CandidateDuplicate.insert_all(pairs, unique_by: "idx_candidate_duplicate_pair")
        last_id = other_ids.last
      end
    end
  end
end
