module Recruitment
  class Planning
    class Forbidden < StandardError; end
    class InvalidTransition < StandardError; end

    def initialize(actor)
      @actor = actor
    end

    def templates
      permit!("read.vacancy_template")
      @actor.allows?("manage.vacancy_template") ? VacancyTemplate.all : VacancyTemplate.where(status: "approved")
    end

    def requisitions
      permit!("read.job_requisition")
      return JobRequisition.all if global_reader?
      JobRequisition.where(recruiter_id: @actor.id).or(JobRequisition.where(department_id: @actor.department_ids))
    end

    def campaigns
      permit!("read.recruitment_campaign")
      global_reader? ? RecruitmentCampaign.all : RecruitmentCampaign.where(recruiter_id: @actor.id)
    end

    def create_template(attributes)
      permit!("manage.vacancy_template")
      VacancyTemplate.transaction do
        template = VacancyTemplate.create!(recruiter_id: attributes["recruiter_id"], created_by: @actor)
        template.versions.create!(attributes.slice(*VacancyTemplateVersion::CONTENT_FIELDS).merge(version_number: 1))
        audit!(template, "vacancy_template.created")
        template
      end
    end

    def revise_template(id, attributes)
      permit!("manage.vacancy_template")
      VacancyTemplate.transaction do
        template = VacancyTemplate.lock.find(id)
        if attributes.key?("recruiter_id") && attributes["recruiter_id"].to_s != template.recruiter_id.to_s && template.recruitment_campaign
          raise InvalidTransition, "recruiter_transfer_requires_separate_workflow"
        end
        content = template.versions.order(version_number: :desc).first
        template.update!(attributes.slice("recruiter_id").merge(status: "draft"))
        template.versions.create!(content.attributes.slice(*VacancyTemplateVersion::CONTENT_FIELDS)
          .merge(attributes.slice(*VacancyTemplateVersion::CONTENT_FIELDS)).merge(version_number: content.version_number + 1))
        audit!(template, "vacancy_template.revised")
        template
      end
    end

    def approve_template(id)
      permit!("approve.vacancy_template")
      VacancyTemplate.transaction do
        template = VacancyTemplate.lock.find(id)
        raise InvalidTransition, "template_already_approved" unless template.status == "draft"
        template.update!(status: "approved")
        audit!(template, "vacancy_template.approved")
        template
      end
    end

    def create_requisition(attributes)
      permit!("create.job_requisition")
      department = Department.find(attributes["department_id"])
      department_access!(department.id)
      JobRequisition.transaction do
        template = VacancyTemplate.lock.find(attributes["vacancy_template_id"])
        raise InvalidTransition, "template_must_be_approved" unless template.status == "approved"
        raise InvalidTransition, "recruiter_is_unavailable" unless template.recruiter.allows?("launch.recruitment_campaign")
        campaign = RecruitmentCampaign.find_or_create_by!(vacancy_template: template) do |record|
          record.recruiter = template.recruiter
        end
        campaign.lock!
        requisition = JobRequisition.create!(department: department, vacancy_template: template,
          vacancy_template_version: template.versions.order(version_number: :desc).first,
          recruitment_campaign: campaign, recruiter: campaign.recruiter, created_by: @actor,
          positions_count: attributes["positions_count"], status: campaign.status == "active" ? "recruiting" : "ready")
        content = attributes.slice(*JobRequisitionVersion::CONTENT_FIELDS)
        if requisition.vacancy_template_version.internship_required? && content["internship_supervisor_id"].blank?
          content["internship_supervisor_id"] = @actor.id
        end
        requisition.versions.create!(content.merge(version_number: 1))
        audit!(requisition, "job_requisition.created")
        requisition
      end
    end

    def revise_requisition(id, attributes)
      permit!("update.job_requisition")
      with_requisition(id) do |requisition, _campaign|
        department_access!(requisition.department_id)
        raise InvalidTransition, "requisition_not_editable" if %w[closed cancelled].include?(requisition.status)
        latest = requisition.versions.order(version_number: :desc).first
        requisition.update!(attributes.slice("positions_count"))
        requisition.versions.create!(latest.attributes.slice(*JobRequisitionVersion::CONTENT_FIELDS)
          .merge(attributes.slice(*JobRequisitionVersion::CONTENT_FIELDS)).merge(version_number: latest.version_number + 1))
        audit!(requisition, "job_requisition.revised")
        requisition
      end
    end

    def launch_campaign(id, search_query:)
      permit!("launch.recruitment_campaign")
      RecruitmentCampaign.transaction do
        campaign = RecruitmentCampaign.lock.find(id)
        recruiter_access!(campaign.recruiter_id)
        raise InvalidTransition, "campaign_already_active" if campaign.status == "active"
        raise InvalidTransition, "no_ready_requisitions" unless campaign.job_requisitions.where(status: "ready").exists?
        campaign.update!(status: "active", search_query: search_query, approved_by: @actor, approved_at: Time.current)
        campaign.job_requisitions.where(status: "ready").order(:id).each do |requisition|
          requisition.update!(status: "recruiting")
          audit!(requisition, "job_requisition.started")
        end
        audit!(campaign, "recruitment_campaign.launched")
        campaign
      end
    end

    def transition_requisition(id, action, allow_next_application: nil)
      permit!("manage.job_requisition")
      with_requisition(id) do |requisition, campaign|
        recruiter_access!(requisition.recruiter_id)
        cancel_applications = action == "cancel" ? active_applications_for_cancellation(requisition, allow_next_application) : []
        target = case action
        when "pause"
          raise InvalidTransition, "requisition_cannot_pause" unless %w[ready recruiting].include?(requisition.status)
          "paused"
        when "resume"
          raise InvalidTransition, "requisition_cannot_resume" unless requisition.status == "paused"
          campaign.status == "active" ? "recruiting" : "ready"
        when "cancel"
          raise InvalidTransition, "requisition_cannot_cancel" unless %w[ready recruiting paused].include?(requisition.status)
          "cancelled"
        else
          raise InvalidTransition, "unsupported_transition"
        end
        cancel_applications.each do |application|
          application.update!(status: "completed", outcome: "cancelled", ended_at: Time.current,
            decided_by: @actor, allow_next_application: allow_next_application, rejection_reason: nil)
          audit!(application, "candidate_application.cancelled")
        end
        requisition.update!(status: target)
        audit!(requisition, "job_requisition.#{action}")
        if campaign.status == "active" && !campaign.job_requisitions.where(status: "recruiting").exists?
          campaign.update!(status: "paused")
          audit!(campaign, "recruitment_campaign.paused")
        end
        requisition
      end
    end

    private

    def active_applications_for_cancellation(requisition, allow_next_application)
      active = CandidateApplication.where(job_requisition: requisition, status: "active")
      return [] unless active.exists?

      unless [ true, false ].include?(allow_next_application)
        raise InvalidTransition, "next_application_decision_required"
      end

      candidate_ids = active.distinct.order(:candidate_id).pluck(:candidate_id)
      Candidate.where(id: candidate_ids).order(:id).lock.load
      CandidateApplication.where(job_requisition: requisition, status: "active")
        .order(:id).lock.to_a
    end

    def with_requisition(id)
      JobRequisition.transaction do
        campaign_id = JobRequisition.where(id: id).pick(:recruitment_campaign_id)
        raise ActiveRecord::RecordNotFound unless campaign_id
        # All mutations use the same lock order: campaign, then requisition.
        campaign = RecruitmentCampaign.lock.find(campaign_id)
        requisition = campaign.job_requisitions.lock.find(id)
        yield requisition, campaign
      end
    end

    def permit!(permission)
      raise Forbidden unless @actor.allows?(permission)
    end

    def department_access!(department_id)
      raise Forbidden unless @actor.admin? || @actor.departments.exists?(id: department_id)
    end

    def recruiter_access!(recruiter_id)
      raise Forbidden unless @actor.admin? || @actor.id == recruiter_id
    end

    def global_reader?
      @actor.admin? || @actor.allows?("read.all_recruitment")
    end

    def audit!(record, action)
      changeset = record.saved_changes
      if record.respond_to?(:versions)
        version = record.versions.order(version_number: :desc).pick(:version_number)
        changeset = changeset.merge("version_number" => version)
      end
      AuditEvent.record!(actor: @actor, action: action, subject: record, changeset: changeset)
    end
  end
end
