module Api
  module V1
    class CandidateResumesController < BaseController
      rescue_from Candidates::ResumeStorage::InvalidUpload do |error|
        render json: { error: "invalid_upload", reason: error.message }, status: :unprocessable_entity
      end

      def index
        records = page_records(CandidateResume.where(candidate: candidate).with_attached_original)
        render json: records.map { |resume| resume_json(resume) }
      end

      def create
        resume, created = Candidates::ResumeStorage.new(current_user).upload(candidate, params[:file])
        render json: resume_json(resume), status: created ? :created : :ok
      end

      def show
        resume = CandidateResume.where(candidate: candidate).with_attached_original.find(params[:id])
        response.set_header("X-Content-Type-Options", "nosniff")
        send_data resume.original.download, filename: resume.original.filename.to_s,
          type: resume.original.content_type, disposition: "attachment"
      end

      private

      def candidate
        @candidate ||= Candidates::Access.new(current_user).visible_candidates.find(params[:candidate_id])
      end

      def resume_json(resume)
        { id: resume.id, candidate_id: resume.candidate_id, uploaded_by_id: resume.uploaded_by_id,
          filename: resume.original.filename.to_s, content_type: resume.original.content_type,
          byte_size: resume.original.byte_size, sha256: resume.sha256, created_at: resume.created_at }
      end
    end
  end
end
