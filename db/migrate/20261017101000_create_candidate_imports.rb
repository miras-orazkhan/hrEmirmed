class CreateCandidateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_imports do |t|
      t.references :created_by, null: false, foreign_key: { to_table: :users }, index: false
      t.string :provider, null: false, default: "prototype"
      t.integer :total_count, null: false
      t.integer :imported_count, null: false
      t.integer :skipped_count, null: false
      t.integer :rejected_count, null: false
      t.jsonb :row_results, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :candidate_imports, [ :created_by_id, :id ]
    add_check_constraint :candidate_imports, "provider = 'prototype'", name: "candidate_imports_provider"
    add_check_constraint :candidate_imports,
      "total_count BETWEEN 1 AND 1000 AND imported_count >= 0 AND skipped_count >= 0 AND rejected_count >= 0 AND total_count = imported_count + skipped_count + rejected_count",
      name: "candidate_imports_counts"
    add_check_constraint :candidate_imports,
      "jsonb_typeof(row_results) = 'array' AND jsonb_array_length(row_results) = total_count",
      name: "candidate_imports_results"
  end
end
