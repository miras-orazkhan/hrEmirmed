class HardenCandidateDecisions < ActiveRecord::Migration[8.1]
  CONSTRAINT = "(outcome IS NOT DISTINCT FROM 'rejected') = (rejection_reason_id IS NOT NULL)"
  PREVIOUS_CONSTRAINT = "(outcome = 'rejected' AND rejection_reason_id IS NOT NULL) OR " \
    "(outcome IS DISTINCT FROM 'rejected' AND rejection_reason_id IS NULL)"

  def up
    remove_check_constraint :candidate_applications, name: "candidate_rejection_reason_required"
    add_check_constraint :candidate_applications, CONSTRAINT, name: "candidate_rejection_reason_required"
  end

  def down
    remove_check_constraint :candidate_applications, name: "candidate_rejection_reason_required"
    add_check_constraint :candidate_applications, PREVIOUS_CONSTRAINT, name: "candidate_rejection_reason_required"
  end
end
