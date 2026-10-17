module Candidates
  class Applications
    def initialize(actor)
      @actor = actor
      @access = Access.new(actor)
    end

    def start(candidate_id:, job_requisition_id:)
      permit!("manage.candidate_application")
      candidate = @access.visible_candidates.find(candidate_id)
      with_requisition(job_requisition_id) do |requisition, campaign|
        assigned!(requisition.recruiter_id)
        recruiting!(requisition, campaign)
        raise Recruitment::Planning::InvalidTransition, "no_remaining_positions" if requisition.filled_positions_count >= requisition.positions_count
        candidate.lock!
        history = CandidateApplication.where(candidate_id: candidate.id)
        raise Recruitment::Planning::InvalidTransition, "candidate_has_active_application" if history.where(status: "active").exists?
        previous = history.order(id: :desc).first
        if previous && previous.allow_next_application != true
          raise Recruitment::Planning::InvalidTransition, "next_application_not_allowed"
        end
        candidate.update!(responsible_recruiter_id: requisition.recruiter_id) if candidate.responsible_recruiter_id != requisition.recruiter_id
        application = CandidateApplication.create!(candidate: candidate, job_requisition: requisition,
          job_requisition_version: requisition.versions.order(version_number: :desc).first, created_by: @actor)
        audit!(application, "candidate_application.started")
        application
      end
    end

    def advance(id)
      mutate(id) do |application, requisition|
        target = case application.stage
        when "screening" then "test_review"
        when "test_review" then "interview"
        when "interview" then requisition.vacancy_template_version.internship_required? ? "internship" : "offer"
        when "internship" then "offer"
        else
          raise Recruitment::Planning::InvalidTransition, "employment_workflow_required"
        end
        application.update!(stage: target)
        audit!(application, "candidate_application.advanced")
      end
    end

    def finish(id, attributes)
      mutate(id) do |application, _requisition|
        unless %w[rejected withdrawn].include?(attributes["outcome"])
          raise Recruitment::Planning::InvalidTransition, "unsupported_outcome"
        end
        unless [ true, false ].include?(attributes["allow_next_application"])
          raise Recruitment::Planning::InvalidTransition, "next_application_decision_required"
        end
        reason = RejectionReason.where(active: true).find(attributes["rejection_reason_id"]) if attributes["outcome"] == "rejected"
        application.update!(attributes.slice("outcome", "decision_comment", "allow_next_application").merge(
          status: "completed", ended_at: Time.current, decided_by: @actor, rejection_reason: reason))
        audit!(application, "candidate_application.completed")
      end
    end

    private

    def mutate(id)
      visible = @access.visible_applications.find(id)
      with_requisition(visible.job_requisition_id) do |requisition, campaign|
        # Candidate lock serializes starts, decisions and cancellation for this person.
        Candidate.lock.find(visible.candidate_id)
        application = CandidateApplication.lock.find(id)
        decision_access!(application, requisition)
        recruiting!(requisition, campaign)
        raise Recruitment::Planning::InvalidTransition, "application_already_completed" unless application.status == "active"
        yield application, requisition
        application
      end
    end

    def with_requisition(id)
      CandidateApplication.transaction do
        campaign_id = JobRequisition.where(id: id).pick(:recruitment_campaign_id)
        raise ActiveRecord::RecordNotFound unless campaign_id
        campaign = RecruitmentCampaign.lock.find(campaign_id)
        requisition = campaign.job_requisitions.lock.find(id)
        yield requisition, campaign
      end
    end

    def decision_access!(application, requisition)
      case application.stage
      when "interview"
        permit!("conduct.interview")
        assigned!(application.job_requisition_version.interviewer_id)
      when "internship"
        permit!("supervise.internship")
        assigned!(application.job_requisition_version.internship_supervisor_id)
      else
        permit!("manage.candidate_application")
        assigned!(requisition.recruiter_id)
      end
    end

    def recruiting!(requisition, campaign)
      unless requisition.status == "recruiting" && campaign.status == "active"
        raise Recruitment::Planning::InvalidTransition, "requisition_not_recruiting"
      end
    end

    def permit!(permission)
      raise Recruitment::Planning::Forbidden unless @actor.allows?(permission)
    end

    def assigned!(user_id)
      raise Recruitment::Planning::Forbidden unless @actor.admin? || @actor.id == user_id
    end

    def audit!(application, action)
      AuditEvent.record!(actor: @actor, action: action, subject: application, changeset: application.saved_changes)
    end
  end
end
