module Web
  class CandidatesController < BaseController
    include WorkflowsHelper
    include CandidateDetails

    before_action :set_candidate, only: %i[show edit update]
    before_action :require_create_permission, only: %i[new create]
    before_action :require_update_permission, only: %i[edit update]

    def index
      scope = Candidates::Access.new(current_user).visible_candidates.includes(:contacts, :sources)
      @query = params[:q].to_s
      scope = search_candidates(scope, @query) if @query.present?
      @candidates = workflow_page(scope)
    end

    def show
      load_candidate_details
    end

    def new
      @candidate = Candidate.new
      @contacts = []
    end

    def create
      @candidate = Candidates::Registry.new(current_user).create(candidate_attributes)
      redirect_to candidate_path(@candidate), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record)
    rescue Recruitment::Planning::Forbidden
      head :forbidden
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue ActionController::ParameterMissing
      @candidate ||= Candidate.new
      @errors = [ "Заполните обязательные поля формы." ]
      @contacts ||= []
      render :new, status: :unprocessable_entity
    end

    def edit
      @contacts = @candidate.contacts.to_a
    end

    def update
      @candidate = Candidates::Registry.new(current_user).update(@candidate.id, candidate_attributes)
      redirect_to candidate_path(@candidate), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record)
    rescue Recruitment::Planning::Forbidden
      head :forbidden
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue ActionController::ParameterMissing
      @errors = [ "Заполните обязательные поля формы." ]
      @contacts ||= @candidate.contacts.to_a
      render :edit, status: :unprocessable_entity
    end

    private

    def require_create_permission
      head :forbidden unless current_user.allows?("create.candidate")
    end

    def require_update_permission
      access = Candidates::Access.new(current_user)
      access.authorize_update!(@candidate)
    end

    def set_candidate
      @candidate = Candidates::Access.new(current_user).visible_candidates
        .includes(:contacts, :sources, :responsible_recruiter).find(params[:id])
    end

    def candidate_attributes
      payload = params.require(:candidate)
      permitted = payload.permit(:full_name, :preferred_language, :city, :summary,
        :responsible_recruiter_id, contacts_attributes: %i[kind value])
      contact_attributes = permitted[:contacts_attributes]
      @contacts = contact_attributes.respond_to?(:values) ? contact_attributes.values : Array(contact_attributes)
      @contacts = @contacts.map(&:to_h).reject { |contact| contact["value"].blank? }
      permitted.to_h.except("contacts_attributes").merge("contacts" => @contacts)
    end

    def search_candidates(scope, query)
      raise ActionController::ParameterMissing, :q if query.length > 200
      phone = CandidateContact.normalize("phone", query)
      email = CandidateContact.normalize("email", query)
      contact_ids = CandidateContact.where(kind: "phone", normalized_value: phone)
        .or(CandidateContact.where(kind: "email", normalized_value: email)).select(:candidate_id)
      prefix = "#{Candidate.sanitize_sql_like(query.downcase)}%"
      scope.where(id: contact_ids).or(scope.where("lower(candidates.full_name) LIKE ?", prefix))
    end

    def invalid_form(record)
      @candidate = record if record.is_a?(Candidate)
      @candidate ||= record.candidate if record.respond_to?(:candidate) && record.candidate
      @candidate ||= Candidate.new
      @errors = validation_messages(record)
      @contacts ||= @candidate.contacts.to_a
      render(action_name == "create" ? :new : :edit, status: :unprocessable_entity)
    end
  end
end
