module Web
  class CandidateApplicationsController < BaseController
    include WorkflowsHelper
    include CandidateDetails

    rescue_from ActiveRecord::RecordInvalid, Recruitment::Planning::InvalidTransition, with: :render_application_error
    def create
      attributes = params.require(:candidate_application).permit(:candidate_id, :job_requisition_id)
      application = Candidates::Applications.new(current_user).start(
        candidate_id: attributes[:candidate_id], job_requisition_id: attributes[:job_requisition_id]
      )
      redirect_to candidate_path(application.candidate_id), status: :see_other
    end

    def advance
      application = visible_application(params[:id])
      result = Candidates::Applications.new(current_user).advance(application.id)
      redirect_to candidate_path(result.candidate_id), status: :see_other
    end

    def finish
      application = visible_application(params[:id])
      attributes = params.require(:candidate_application)
        .permit(:outcome, :rejection_reason_id, :decision_comment, :allow_next_application).to_h
      if attributes["outcome"] == "rejected" && !RejectionReason.where(active: true, id: attributes["rejection_reason_id"]).exists?
        raise Recruitment::Planning::InvalidTransition, "rejection_reason_required"
      end
      attributes["allow_next_application"] = normalize_boolean(attributes["allow_next_application"])
      result = Candidates::Applications.new(current_user).finish(application.id, attributes)
      redirect_to candidate_path(result.candidate_id), status: :see_other
    end

    private

    def render_application_error(error)
      application = visible_application(params[:id]) if params[:id]
      candidate_id = application&.candidate_id || params.dig(:candidate_application, :candidate_id)
      @candidate = Candidates::Access.new(current_user).visible_candidates
        .includes(:contacts, :sources, :responsible_recruiter).find(candidate_id)
      @decision_application_id = application&.id
      @errors = error.is_a?(ActiveRecord::RecordInvalid) ? validation_messages(error.record) : [ workflow_error_message(error) ]
      load_candidate_details
      render "web/candidates/show", status: :unprocessable_entity
    end

    def visible_application(id)
      Candidates::Access.new(current_user).visible_applications.find(id)
    end

    def normalize_boolean(value)
      return true if value == true || value == "true" || value == "1"
      return false if value == false || value == "false" || value == "0"
      value
    end
  end
end
