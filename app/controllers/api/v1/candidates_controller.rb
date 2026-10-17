module Api
  module V1
    class CandidatesController < BaseController
      CANDIDATE_FIELDS = %i[id full_name preferred_language city summary responsible_recruiter_id created_by_id created_at updated_at].freeze

      def index
        scope = access.visible_candidates.includes(:contacts, :sources)
        scope = search(scope) if params[:q].present?
        records = page_records(scope)
        render json: records.map { |candidate| candidate_json(candidate) }
      end

      def show
        render json: candidate_json(access.visible_candidates.includes(:contacts, :sources).find(params[:id]))
      end

      def create
        candidate = Candidates::Registry.new(current_user).create(candidate_params.to_h)
        render json: candidate_json(candidate), status: :created
      end

      def update
        candidate = Candidates::Registry.new(current_user).update(params[:id], candidate_params.to_h)
        render json: candidate_json(candidate)
      end

      private

      def access
        @access ||= Candidates::Access.new(current_user)
      end

      def candidate_params
        payload = params[:candidate]
        raise ActionController::ParameterMissing, :candidate unless payload.is_a?(ActionController::Parameters)

        permitted = %i[full_name preferred_language city summary]
        permitted << :responsible_recruiter_id if action_name == "create"
        nested = { contacts: %i[kind value] }
        nested[:sources] = %i[provider external_id] if action_name == "create"
        payload.permit(*permitted, **nested)
      end

      def search(scope)
        query = params[:q].to_s
        raise ActionController::ParameterMissing, :q if query.length > 200

        phone = CandidateContact.normalize("phone", query)
        email = CandidateContact.normalize("email", query)
        ids = CandidateContact.where(kind: "phone", normalized_value: phone)
          .or(CandidateContact.where(kind: "email", normalized_value: email)).select(:candidate_id)
        prefix = "#{Candidate.sanitize_sql_like(query.downcase)}%"
        scope.where(id: ids).or(scope.where("lower(candidates.full_name) LIKE ?", prefix))
      end

      def candidate_json(candidate)
        candidate.as_json(only: CANDIDATE_FIELDS).merge(
          "contacts" => candidate.contacts.map { |contact| contact.as_json(only: %i[id kind value]) },
          "sources" => candidate.sources.map { |source| source.as_json(only: %i[id provider external_id]) }
        )
      end
    end
  end
end
