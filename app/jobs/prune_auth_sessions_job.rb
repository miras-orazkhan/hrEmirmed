class PruneAuthSessionsJob < ApplicationJob
  queue_as :default

  def perform
    AuthSession.where(expires_at: ...Time.current).in_batches(of: 1_000).delete_all
  end
end
