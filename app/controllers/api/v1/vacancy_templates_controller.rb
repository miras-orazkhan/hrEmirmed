module Api
  module V1
    class VacancyTemplatesController < BaseController
      def index
        render json: page_records(planning.templates.preload(:latest_version)).map { |record| template_json(record) }
      end

      def show
        render json: template_json(planning.templates.find(params[:id]))
      end

      def create
        render json: template_json(planning.create_template(template_params)), status: :created
      end

      def update
        render json: template_json(planning.revise_template(params[:id], template_params))
      end

      def approve
        render json: template_json(planning.approve_template(params[:id]))
      end

      def versions
        template = planning.templates.find(params[:id])
        render json: page_records(template.versions)
      end

      private

      def planning
        Recruitment::Planning.new(current_user)
      end

      def template_params
        params.require(:vacancy_template).permit(:recruiter_id, :title, :duties, :internship_required,
          professional_skills: [], mandatory_requirements: [], preferred_requirements: [],
          screening_questions: [], internship_criteria: []).to_h
      end

      def template_json(record)
        record.as_json.merge("current_version" => record.latest_version.as_json)
      end
    end
  end
end
