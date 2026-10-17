module Web
  module CandidateDetails
    private

    def load_candidate_details
      access = Candidates::Access.new(current_user)
      @applications = access.visible_applications.where(candidate_id: @candidate.id)
        .includes(:job_requisition_version, :rejection_reason, job_requisition: [ :department, :vacancy_template_version, :recruitment_campaign ])
        .order(id: :desc).limit(50)
      @resumes = @candidate.resumes.with_attached_original.includes(:uploaded_by).order(id: :desc).limit(50)
      @available_requisitions = if current_user.allows?("read.job_requisition") && current_user.allows?("manage.candidate_application")
        scope = Recruitment::Planning.new(current_user).requisitions.where(status: "recruiting")
        scope = scope.where(recruiter_id: current_user.id) unless current_user.admin?
        scope.includes(:department, :vacancy_template_version).order(id: :desc).limit(50)
      else
        JobRequisition.none
      end
      @rejection_reasons = RejectionReason.where(active: true).order(:name)
    end
  end
end
