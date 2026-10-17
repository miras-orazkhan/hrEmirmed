module Candidates
  class Importer
    MAX_BYTES = 5 * 1024 * 1024
    MAX_ROWS = 1000
    FIELDS = %w[full_name preferred_language city summary].freeze
    class InvalidInput < StandardError; end
    class Forbidden < StandardError; end

    def initialize(actor)
      @actor = actor
    end

    def call(rows)
      raise Forbidden unless @actor.allows?("import.candidate")
      unless rows.is_a?(Array) && rows.size.between?(1, MAX_ROWS) && rows.to_json.bytesize <= MAX_BYTES
        raise InvalidInput
      end

      # Keep candidates and their reconciliation report atomic. Each savepoint
      # isolates one invalid row, including a concurrent external-ID collision.
      CandidateImport.transaction do
        results = rows.each_with_index.map { |row, index| import_row(row).merge("row_number" => index + 1) }
        report = CandidateImport.create!(created_by: @actor, provider: "prototype", total_count: rows.size,
          imported_count: results.count { |row| row["status"] == "imported" },
          skipped_count: results.count { |row| row["status"] == "skipped" },
          rejected_count: results.count { |row| row["status"] == "rejected" }, row_results: results)
        AuditEvent.record!(actor: @actor, action: "candidate_import.completed", subject: report)
        report
      end
    end

    private

    def import_row(row)
      return rejected("invalid_row") unless row.is_a?(Hash)
      row = row.stringify_keys
      external_id = row["external_id"]
      unless external_id.is_a?(String) && external_id.strip.length.between?(1, 200)
        return rejected("invalid_external_id")
      end
      external_id = external_id.strip
      source = { provider: "prototype", external_id: external_id }
      return { "status" => "skipped" } if CandidateSource.exists?(source)
      unless (FIELDS + %w[phone email]).all? { |field| row[field].nil? || row[field].is_a?(String) }
        return rejected("invalid_field_type")
      end

      Candidate.transaction(requires_new: true) do
        attributes = row.slice(*FIELDS).compact
        attributes["sources"] = [ source.stringify_keys ]
        attributes["contacts"] = %w[phone email].filter_map do |kind|
          { "kind" => kind, "value" => row[kind] } if row[kind].present?
        end
        candidate = Registry.new(@actor).create(attributes, permission: "import.candidate")
        { "status" => "imported", "candidate_id" => candidate.id }
      end
    rescue ActiveRecord::RecordNotUnique
      CandidateSource.exists?(source) ? { "status" => "skipped" } : rejected("conflict")
    rescue ActiveRecord::RecordInvalid
      CandidateSource.exists?(source) ? { "status" => "skipped" } : rejected("validation_failed")
    rescue ActiveRecord::InvalidForeignKey
      rejected("invalid_reference")
    end

    def rejected(code)
      { "status" => "rejected", "code" => code }
    end
  end
end
