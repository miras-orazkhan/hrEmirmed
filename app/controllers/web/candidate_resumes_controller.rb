module Web
  class CandidateResumesController < BaseController
    include WorkflowsHelper
    before_action :set_candidate

    def index
      @resumes = workflow_page(@candidate.resumes.with_attached_original.includes(:uploaded_by).order(id: :asc))
    end

    def create
      resume, = Candidates::ResumeStorage.new(current_user).upload(@candidate, params[:file])
      redirect_to candidate_resumes_path(@candidate), status: :see_other
    rescue Candidates::ResumeStorage::InvalidUpload
      @errors = [ "Не удалось загрузить резюме. Проверьте формат и размер файла." ]
      @resumes = @candidate.resumes.with_attached_original.includes(:uploaded_by).order(id: :asc).limit(50)
      render :index, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => error
      @errors = validation_messages(error.record)
      @resumes = @candidate.resumes.with_attached_original.includes(:uploaded_by).order(id: :asc).limit(50)
      render :index, status: :unprocessable_entity
    rescue Recruitment::Planning::Forbidden
      head :forbidden
    end

    def show
      resume = @candidate.resumes.with_attached_original.find(params[:id])
      response.set_header("Cache-Control", "no-store")
      response.set_header("X-Content-Type-Options", "nosniff")
      send_data resume.original.download, filename: resume.original.filename.to_s,
        type: resume.original.content_type, disposition: "attachment"
    end

    private

    def set_candidate
      @candidate = Candidates::Access.new(current_user).visible_candidates.find(params[:candidate_id])
    end
  end
end
