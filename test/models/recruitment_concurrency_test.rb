require "test_helper"
require "timeout"

class RecruitmentConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @branch = Branch.create!(name: "Concurrent #{suffix}")
    @department = @branch.departments.create!(name: "HR")
    @role = Role.create!(name: "concurrent_#{suffix}", permissions: Role::PERMISSIONS)
    @user = User.create!(login: "concurrent_#{suffix}", full_name: "Concurrency Test", password: "long-test-password",
      branch: @branch, departments: [ @department ], role: @role)
    planner = Recruitment::Planning.new(@user)
    @template = planner.create_template({ "recruiter_id" => @user.id, "title" => "Doctor", "duties" => "Patient care" })
    planner.approve_template(@template.id)
    @attributes = { "department_id" => @department.id, "vacancy_template_id" => @template.id,
      "positions_count" => 2, "salary_amount" => "500000", "salary_currency" => "KZT",
      "work_schedule" => "5/2", "desired_start_on" => "2026-12-01", "interviewer_id" => @user.id,
      "interview_format" => "onsite" }
  end

  teardown do
    if @user&.persisted?
      AuditEvent.where(actor_user_id: @user.id).delete_all
      requisitions = JobRequisition.where(created_by_id: @user.id)
      JobRequisitionVersion.where(job_requisition_id: requisitions.select(:id)).delete_all
      requisitions.delete_all
      templates = VacancyTemplate.where(created_by_id: @user.id)
      RecruitmentCampaign.where(vacancy_template_id: templates.select(:id)).delete_all
      VacancyTemplateVersion.where(vacancy_template_id: templates.select(:id)).delete_all
      templates.delete_all
      @user.destroy!
    end
    @role&.destroy!
    @department&.destroy!
    @branch&.reload&.destroy!
  end

  test "simultaneous requests create one campaign" do
    ids = simultaneously do |planner|
      planner.create_requisition(@attributes).id
    end
    assert_equal 2, ids.uniq.size
    assert_equal 1, RecruitmentCampaign.where(vacancy_template_id: @template.id).count
    assert_equal 1, JobRequisition.where(id: ids).distinct.count(:recruitment_campaign_id)
  end

  test "simultaneous launches produce exactly one approval and one transition" do
    requisition = Recruitment::Planning.new(@user).create_requisition(@attributes)
    results = simultaneously do |planner|
      planner.launch_campaign(requisition.recruitment_campaign_id, search_query: "Doctor")
      :launched
    rescue Recruitment::Planning::InvalidTransition
      :rejected
    end
    assert_equal [ :launched, :rejected ], results.sort
    assert_equal "recruiting", requisition.reload.status
    assert_equal 1, AuditEvent.where(actor_user_id: @user.id, action: "recruitment_campaign.launched").count
    assert_equal 1, AuditEvent.where(actor_user_id: @user.id, action: "job_requisition.started").count
  end

  private

  def simultaneously
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          planner = Recruitment::Planning.new(User.find(@user.id))
          ready << true
          start.pop
          yield planner
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      threads.map(&:value)
    end
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end
end
