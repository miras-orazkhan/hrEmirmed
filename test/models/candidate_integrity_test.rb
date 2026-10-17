require "test_helper"

class CandidateIntegrityTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    @branch = Branch.create!(name: "Integrity #{suffix}")
    @department = @branch.departments.create!(name: "HR")
    @role = Role.create!(name: "integrity_#{suffix}", permissions: Role::PERMISSIONS)
    @user = User.create!(login: "integrity_#{suffix}", full_name: "Integrity recruiter",
      password: "long-test-password", branch: @branch, departments: [ @department ], role: @role)
    @candidate = Candidate.create!(full_name: "Integrity candidate", created_by: @user, responsible_recruiter: @user)
    @reason = RejectionReason.create!(name: "Integrity reason")
    @requisitions = 2.times.map { create_requisition(suffix) }
  end

  test "database requires reasons exactly for rejected applications" do
    assert_database_rejects(ActiveRecord::StatementInvalid) do
      CandidateApplication.insert_all!([ application_attributes(requisition: @requisitions.first,
        rejection_reason_id: @reason.id) ])
    end

    assert_database_rejects(ActiveRecord::StatementInvalid) do
      CandidateApplication.insert_all!([ application_attributes(requisition: @requisitions.first,
        status: "completed", outcome: "withdrawn", ended_at: Time.current, decided_by_id: @user.id,
        allow_next_application: false, rejection_reason_id: @reason.id) ])
    end
  end

  test "database allows at most one active application per candidate" do
    first = application_attributes(requisition: @requisitions.first)
    CandidateApplication.insert_all!([ first ])

    assert_database_rejects(ActiveRecord::RecordNotUnique) do
      CandidateApplication.insert_all!([ application_attributes(requisition: @requisitions.second) ])
    end
  end

  test "database rejects application version from a different requisition" do
    assert_database_rejects(ActiveRecord::InvalidForeignKey) do
      CandidateApplication.insert_all!([ application_attributes(requisition: @requisitions.first,
        version: @requisitions.second.versions.first) ])
    end
  end

  private

  def create_requisition(suffix)
    planning = Recruitment::Planning.new(@user)
    template = planning.create_template({ "title" => "Doctor #{suffix}", "duties" => "Patient care",
      "recruiter_id" => @user.id })
    planning.approve_template(template.id)
    requisition = planning.create_requisition({ "department_id" => @department.id,
      "vacancy_template_id" => template.id, "positions_count" => 2, "salary_amount" => "500000",
      "salary_currency" => "KZT", "work_schedule" => "5/2", "desired_start_on" => "2026-12-01",
      "interviewer_id" => @user.id, "interview_format" => "onsite" })
    planning.launch_campaign(requisition.recruitment_campaign_id, search_query: "Doctor")
    requisition
  end

  def application_attributes(requisition:, version: requisition.versions.first, **overrides)
    {
      candidate_id: @candidate.id,
      job_requisition_id: requisition.id,
      job_requisition_version_id: version.id,
      created_by_id: @user.id,
      stage: "screening",
      status: "active",
      created_at: Time.current,
      updated_at: Time.current
    }.merge(overrides)
  end

  def assert_database_rejects(error)
    assert_raises(error) do
      ApplicationRecord.transaction(requires_new: true) do
        yield
        ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    end
  end
end
