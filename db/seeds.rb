Role.find_or_create_by!(name: "admin")

# Bootstrap is explicit: no default password and no invented organization records.
if ENV["ADMIN_LOGIN"].present? && !User.exists?(login: ENV["ADMIN_LOGIN"].strip.downcase)
  User.transaction do
    branch = Branch.find_or_create_by!(name: ENV.fetch("ADMIN_BRANCH"))
    department = branch.departments.find_or_create_by!(name: ENV.fetch("ADMIN_DEPARTMENT"))
    User.create!(login: ENV.fetch("ADMIN_LOGIN"), full_name: ENV.fetch("ADMIN_NAME"),
      password: ENV.fetch("ADMIN_PASSWORD"), role: Role.find_by!(name: "admin"),
      branch: branch, departments: [ department ])
  end
end

# Presets are only created once; subsequent seeds preserve administrator edits.
{
  "hr_manager" => %w[read.organization read.vacancy_template manage.vacancy_template approve.vacancy_template
    read.job_requisition read.recruitment_campaign read.all_recruitment read.audit read.candidate create.candidate
    update.candidate import.candidate manage.candidate_application read.all_candidates resolve.candidate_duplicate
    manage.all_candidate_duplicates
    manage.rejection_reason],
  "recruiter" => %w[read.organization read.vacancy_template read.job_requisition manage.job_requisition
    read.recruitment_campaign launch.recruitment_campaign conduct.interview read.candidate read.all_candidates
    create.candidate update.candidate import.candidate manage.candidate_application resolve.candidate_duplicate],
  "department_manager" => %w[read.organization read.vacancy_template read.job_requisition
    create.job_requisition update.job_requisition conduct.interview supervise.internship read.candidate]
}.each do |name, permissions|
  Role.find_or_create_by!(name: name) { |role| role.permissions = permissions }
end
