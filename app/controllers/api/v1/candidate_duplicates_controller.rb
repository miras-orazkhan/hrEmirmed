module Api
  module V1
    class CandidateDuplicatesController < BaseController
      def index
        records = page_records(duplicates.visible)
        render json: records.map { |duplicate| duplicate_json(duplicate) }
      end

      def resolve
        payload = params[:candidate_duplicate]
        raise ActionController::ParameterMissing, :candidate_duplicate unless payload.is_a?(ActionController::Parameters)

        attributes = payload.permit(:status, :resolution_note).to_h
        duplicate = duplicates.resolve(params[:id], attributes)
        render json: duplicate_json(duplicate)
      end

      private

      def duplicates
        @duplicates ||= Candidates::Duplicates.new(current_user)
      end

      def duplicate_json(duplicate)
        first = duplicate.candidate
        second = duplicate.other_candidate
        {
          id: duplicate.id,
          candidate_id: first.id,
          other_candidate_id: second.id,
          status: duplicate.status,
          requires_hr_review: duplicate.requires_hr_review?,
          assignee_user_id: duplicate.requires_hr_review? ? nil : first.responsible_recruiter_id,
          resolved_by_id: duplicate.resolved_by_id,
          resolved_at: duplicate.resolved_at,
          created_at: duplicate.created_at
        }
      end
    end
  end
end
