require "test_helper"
require "tempfile"

class CandidateResumesTest < ActionDispatch::IntegrationTest
  setup do
    branch = Branch.create!(name: "Resume branch")
    department = branch.departments.create!(name: "Resume department")
    role = Role.create!(name: "admin")
    @actor = User.create!(login: "resume_admin", full_name: "Resume admin", role: role,
      branch: branch, departments: [ department ], password: "long-test-password")
    @candidate = Candidate.create!(full_name: "Resume candidate", created_by: @actor,
      responsible_recruiter: @actor)
    _, token = AuthSession.issue!(@actor)
    @headers = { "Authorization" => "Bearer #{token}" }
    @temporary_files = []
    @created_blob_ids = []
  end

  teardown do
    ActiveStorage::Blob.where(id: @created_blob_ids).each { |blob| blob.service.delete(blob.key) }
    @temporary_files.each(&:close!)
  end

  test "original upload is private and duplicate bytes are idempotent" do
    bytes = "%PDF-1.7\nOriginal resume\n%%EOF\n"
    upload(bytes)
    assert_response :created
    payload = response.parsed_body
    assert_equal Digest::SHA256.hexdigest(bytes), payload["sha256"]
    assert_equal bytes.bytesize, payload["byte_size"]
    @created_blob_ids << CandidateResume.find(payload["id"]).original.blob_id
    assert_no_difference [ "CandidateResume.count", "ActiveStorage::Blob.count" ] do
      upload(bytes)
    end
    assert_response :ok
    assert_equal payload["id"], response.parsed_body["id"]

    get "#{endpoint}/#{payload['id']}"
    assert_response :unauthorized
    get "#{endpoint}/#{payload['id']}", headers: @headers
    assert_response :success
    assert_equal bytes, response.body
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "no-store", response.headers["Cache-Control"]

    blob = CandidateResume.find(payload["id"]).original.blob
    get "/rails/active_storage/blobs/redirect/#{blob.signed_id}/resume.pdf"
    assert_response :not_found
  end

  test "missing oversized and disguised executable uploads leave no storage rows" do
    assert_no_difference [ "CandidateResume.count", "ActiveStorage::Blob.count" ] do
      post endpoint, headers: @headers
      assert_response :unprocessable_entity
      upload("MZ\x00\x00executable", name: "resume.pdf")
      assert_response :unprocessable_entity
      upload("%PDF-1.7\n", name: "resume.exe")
      assert_response :unprocessable_entity
      upload("x" * (Candidates::ResumeStorage::MAX_BYTES + 1), name: "resume.txt")
      assert_response :unprocessable_entity
    end
  end

  test "valid plain text and DOCX resumes are accepted with detected content types" do
    text_bytes = "Опыт работы: врач-терапевт\n".encode(Encoding::UTF_8)
    upload(text_bytes, name: "resume.txt")
    assert_response :created
    text_resume = CandidateResume.find(response.parsed_body.fetch("id"))
    @created_blob_ids << text_resume.original.blob_id
    assert_equal "text/plain", text_resume.original.content_type
    assert_equal text_bytes.b, text_resume.original.download

    docx_bytes = Rails.root.join("test/fixtures/files/minimal_resume.docx").binread
    upload(docx_bytes, name: "resume.docx")
    assert_response :created
    docx_resume = CandidateResume.find(response.parsed_body.fetch("id"))
    @created_blob_ids << docx_resume.original.blob_id
    assert_equal "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      docx_resume.original.content_type
    assert_equal docx_bytes, docx_resume.original.download
  end

  test "unrelated user cannot read or upload candidate resume" do
    upload("%PDF-1.7\nprivate\n")
    assert_response :created
    resume = CandidateResume.find(response.parsed_body["id"])
    @created_blob_ids << resume.original.blob_id
    role = Role.create!(name: "resume_interviewer", permissions: %w[read.candidate conduct.interview])
    stranger = User.create!(login: "resume_stranger", full_name: "Stranger", role: role,
      branch: @actor.branch, departments: @actor.departments, password: "long-test-password")
    _, token = AuthSession.issue!(stranger)
    @headers = { "Authorization" => "Bearer #{token}" }
    get "#{endpoint}/#{resume.id}", headers: @headers
    assert_response :not_found
    upload("%PDF-1.7\nsecond\n")
    assert_response :not_found
  end

  test "failed persistence removes database rows and uploaded bytes" do
    candidate = @candidate
    service = ActiveStorage::Blob.service
    delete_method = service.method(:delete)
    deleted_keys = []
    candidate.define_singleton_method(:with_lock) do |**_options, &block|
      candidate.class.transaction(requires_new: true) do
        block.call
        raise "rollback"
      end
    end
    service.define_singleton_method(:delete) do |key|
      deleted_keys << key
      delete_method.call(key)
    end

    assert_no_difference [ "CandidateResume.count", "ActiveStorage::Blob.count" ] do
      assert_raises(RuntimeError) do
        file = uploaded_file("%PDF-1.7\nfailed\n", "resume.pdf")
        request_file = ActionDispatch::Http::UploadedFile.new(tempfile: file.tempfile,
          filename: "resume.pdf", type: "application/pdf")
        Candidates::ResumeStorage.new(@actor).upload(candidate, request_file)
      end
    end
    assert_equal 1, deleted_keys.size
    assert_not service.exist?(deleted_keys.first)
  ensure
    candidate&.singleton_class&.remove_method(:with_lock) if candidate&.singleton_class&.instance_methods(false)&.include?(:with_lock)
    service&.singleton_class&.remove_method(:delete) if service&.singleton_class&.instance_methods(false)&.include?(:delete)
  end

  private

  def endpoint
    "/api/v1/candidates/#{@candidate.id}/resumes"
  end

  def upload(bytes, name: "resume.pdf")
    post endpoint, params: { file: uploaded_file(bytes, name) }, headers: @headers
  end

  def uploaded_file(bytes, name)
    tempfile = Tempfile.new([ "candidate-resume", File.extname(name) ])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    @temporary_files << tempfile
    Rack::Test::UploadedFile.new(tempfile.path, "application/pdf", true, original_filename: name)
  end
end
