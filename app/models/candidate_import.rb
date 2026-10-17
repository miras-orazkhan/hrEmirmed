class CandidateImport < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  validates :provider, inclusion: { in: [ "prototype" ] }
  validates :total_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }
  validates :imported_count, :skipped_count, :rejected_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def readonly?
    persisted?
  end
end
