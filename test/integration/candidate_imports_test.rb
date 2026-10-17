require "test_helper"

class CandidateImportsTest < ActionDispatch::IntegrationTest
  setup do
    @branch = Branch.create!(name: "Import branch")
    @department = @branch.departments.create!(name: "Import department")
    @importer = staff("importer", [ "import.candidate" ])
    @other_importer = staff("other_importer", [ "import.candidate" ])
    @reader = staff("reader", [ "read.candidate" ])
  end

  test "import-only permission creates candidates and persists a sanitized reconciliation report" do
    assert_difference "Candidate.count", 1 do
      import_rows([
        { external_id: "prototype-1", full_name: "Кандидат", phone: "+77011234567", email: "PERSON@EXAMPLE.COM" },
        { external_id: "prototype-2", full_name: "Private rejected name", email: "secret-invalid-email" },
        { full_name: "Private missing identifier" }
      ])
    end
    assert_response :created
    report = response.parsed_body
    assert_equal 3, report["total_count"]
    assert_equal 1, report["imported_count"]
    assert_equal 2, report["rejected_count"]
    assert_equal [ 1, 2, 3 ], report["row_results"].pluck("row_number")
    assert_equal "validation_failed", report["row_results"][1]["code"]
    assert_equal "invalid_external_id", report["row_results"][2]["code"]
    assert_equal @importer.id, Candidate.last.responsible_recruiter_id
    assert_equal "person@example.com", Candidate.last.contacts.find_by!(kind: "email").normalized_value
    refute_match(/secret-invalid-email|Private rejected name|Private missing identifier|PERSON@EXAMPLE.COM/, CandidateImport.last.to_json)
    assert AuditEvent.exists?(action: "candidate_import.completed", subject_id: report["id"])
  end

  test "duplicate external identifiers within batch and repeated import do not overwrite candidates" do
    rows = [ { external_id: "stable-1", full_name: "Original" }, { external_id: "stable-1", full_name: "Overwrite" } ]
    assert_difference "Candidate.count", 1 do
      import_rows(rows)
    end
    assert_response :created
    assert_equal 1, response.parsed_body["skipped_count"]
    assert_equal "Original", Candidate.last.full_name
    assert_no_difference "Candidate.count" do
      import_rows(rows)
    end
    assert_response :created
    assert_equal 2, response.parsed_body["skipped_count"]
    assert_equal "Original", Candidate.last.full_name
  end

  test "identical names with distinct source identifiers remain separate and row ownership is ignored" do
    assert_difference "Candidate.count", 2 do
      import_rows([
        { external_id: "same-name-1", full_name: "Same name", responsible_recruiter_id: @other_importer.id,
          created_by_id: @other_importer.id, sources: [ { provider: "headhunter", external_id: "inject" } ] },
        { external_id: "same-name-2", full_name: "Same name" }
      ])
    end
    assert_response :created
    assert_equal [ @importer.id ], Candidate.distinct.pluck(:responsible_recruiter_id)
    assert_equal [ "prototype" ], CandidateSource.distinct.pluck(:provider)
  end

  test "import permission and report ownership are enforced" do
    post "/api/v1/candidate_imports", params: { candidate_import: { rows: [ { external_id: "one", full_name: "Name" } ] } }, headers: auth(@reader), as: :json
    assert_response :forbidden
    assert_equal 0, Candidate.count
    import_rows([ { external_id: "one", full_name: "Name" } ])
    report = CandidateImport.last
    get "/api/v1/candidate_imports/#{report.id}", headers: auth(@other_importer)
    assert_response :not_found
    get "/api/v1/candidate_imports", headers: auth(@other_importer)
    assert_equal [], response.parsed_body
    get "/api/v1/candidate_imports/#{report.id}", headers: auth(@importer)
    assert_response :success
    assert_equal 1, response.parsed_body["row_results"].size
  end

  test "list uses pagination without loading row results" do
    import_rows([ { external_id: "one", full_name: "Name" } ])
    first = CandidateImport.last
    import_rows([ { external_id: "two", full_name: "Name" } ])
    get "/api/v1/candidate_imports", params: { limit: 1 }, headers: auth(@importer)
    assert_response :success
    assert_equal 1, response.parsed_body.size
    refute response.parsed_body.first.key?("row_results")
    cursor = response.headers.fetch("X-Next-Cursor")
    get "/api/v1/candidate_imports", params: { limit: 1, cursor: cursor }, headers: auth(@importer)
    assert_equal first.id, response.parsed_body.first["id"]
  end

  test "invalid batch shape and oversized batch are rejected before writing" do
    assert_no_difference "CandidateImport.count" do
      [ [], "invalid", Array.new(1001) { { external_id: "one", full_name: "Name" } } ].each do |rows|
        import_rows(rows)
        assert_response :unprocessable_entity
      end
      import_rows([ { external_id: "one", full_name: "Name", summary: "x" * Candidates::Importer::MAX_BYTES } ])
      assert_response 413
    end
    assert_equal 0, Candidate.count
  end

  test "malformed rows are rejected individually and a valid later row is imported" do
    import_rows([ 42, { external_id: { value: "one" }, full_name: "Name" },
      { external_id: "two", full_name: [ "Name" ] }, { external_id: "three", full_name: "Name" } ])
    assert_response :created
    assert_equal 3, response.parsed_body["rejected_count"]
    assert_equal 1, response.parsed_body["imported_count"]
    assert_equal 1, Candidate.count
  end

  test "malformed import envelopes are rejected without writes" do
    assert_no_difference "CandidateImport.count" do
      [ nil, "invalid", 42, [], [ "invalid" ], {} ].each do |payload|
        post "/api/v1/candidate_imports", params: { candidate_import: payload }, headers: auth(@importer), as: :json
        assert_response :unprocessable_entity
      end
    end
  end

  test "external identifiers exceeding storage limits have explicit errors" do
    import_rows([ { external_id: "x" * 201, full_name: "Name" } ])
    assert_response :created
    assert_equal "invalid_external_id", response.parsed_body["row_results"].first["code"]
    assert_equal 0, Candidate.count
  end

  private

  def staff(login, permissions)
    role = Role.create!(name: login, permissions: permissions)
    User.create!(login: login, full_name: login, password: "long-test-password", role: role,
      branch: @branch, departments: [ @department ])
  end

  def auth(user)
    _, token = AuthSession.issue!(user)
    { "Authorization" => "Bearer #{token}" }
  end

  def import_rows(rows)
    post "/api/v1/candidate_imports", params: { candidate_import: { rows: rows } }, headers: auth(@importer), as: :json
  end
end
