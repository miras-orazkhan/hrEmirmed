module Candidates
  class Access
    def initialize(actor)
      @actor = actor
    end

    def visible_candidates
      permit!("read.candidate")
      return Candidate.all if @actor.allows?("read.all_candidates")
      Candidate.where(id: visible_applications.select(:candidate_id))
    end

    def visible_applications
      permit!("read.candidate")
      return CandidateApplication.all if @actor.allows?("read.all_candidates")
      # A department assignment alone never exposes candidate dossiers.
      versions = JobRequisitionVersion.arel_table
      applications = CandidateApplication.arel_table
      predicates = []
      if @actor.allows?("conduct.interview")
        predicates << versions[:interviewer_id].eq(@actor.id).and(applications[:stage].in(%w[interview internship offer]))
      end
      if @actor.allows?("supervise.internship")
        predicates << versions[:internship_supervisor_id].eq(@actor.id).and(applications[:stage].in(%w[internship offer]))
      end
      return CandidateApplication.none if predicates.empty?

      CandidateApplication.joins(:job_requisition_version).where(predicates.reduce(&:or))
    end

    def authorize_update!(candidate)
      permit!("update.candidate")
      return if @actor.admin?
      application = candidate.applications.find_by(status: "active")
      owner_id = application ? application.job_requisition.recruiter_id : candidate.responsible_recruiter_id
      raise Recruitment::Planning::Forbidden unless owner_id == @actor.id
      if application && application.job_requisition.status != "recruiting"
        raise Recruitment::Planning::InvalidTransition, "requisition_not_recruiting"
      end
    end

    private

    def permit!(permission)
      raise Recruitment::Planning::Forbidden unless @actor.allows?(permission)
    end
  end
end
