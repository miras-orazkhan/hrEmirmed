module Api
  module V1
    class CandidateImportsController < BaseController
      before_action -> { authorize!("import.candidate") }

      rescue_from Candidates::Importer::Forbidden do
        render json: { error: "forbidden" }, status: :forbidden
      end
      rescue_from Candidates::Importer::InvalidInput do
        render json: { error: "invalid_import", max_rows: Candidates::Importer::MAX_ROWS,
          max_bytes: Candidates::Importer::MAX_BYTES }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::Deadlocked, ActiveRecord::SerializationFailure do
        render json: { error: "import_conflict", retryable: true }, status: :conflict
      end

      def index
        render json: page_records(imports.select(*summary_columns), descending: true)
      end

      def show
        render json: imports.find(params[:id])
      end

      def create
        if request.raw_post.bytesize > Candidates::Importer::MAX_BYTES
          return render json: { error: "import_too_large" }, status: :content_too_large
        end
        payload = params[:candidate_import]
        raise Candidates::Importer::InvalidInput unless payload.is_a?(ActionController::Parameters)
        rows = payload[:rows]
        rows = rows.map { |row| row.is_a?(ActionController::Parameters) ? row.to_unsafe_h : row } if rows.is_a?(Array)
        render json: Candidates::Importer.new(current_user).call(rows), status: :created
      end

      private

      def imports
        current_user.admin? ? CandidateImport.all : CandidateImport.where(created_by_id: current_user.id)
      end

      def summary_columns
        %i[id created_by_id provider total_count imported_count skipped_count rejected_count created_at]
      end
    end
  end
end
