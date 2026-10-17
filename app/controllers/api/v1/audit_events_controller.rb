module Api
  module V1
    class AuditEventsController < BaseController
      before_action -> { authorize!("read.audit") }

      def index
        render json: page_records(AuditEvent.all, descending: true)
      end
    end
  end
end
