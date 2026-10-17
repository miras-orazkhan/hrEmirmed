# Run: RAILS_ENV=test bin/rails runner script/benchmark_database.rb
# All synthetic rows are rolled back; never use a shared/live test database.
abort "This benchmark only runs in test" unless Rails.env.test?

require "benchmark"

ApplicationRecord.transaction do
  connection = ApplicationRecord.connection
  suffix = SecureRandom.hex(6)
  branch = Branch.create!(name: "Benchmark #{suffix}")
  department = branch.departments.create!(name: "HR")
  role = Role.create!(name: "benchmark_#{suffix}")
  digest = BCrypt::Password.create("benchmark-password").to_s
  rows = 10_000.times.map do |i|
    { login: "bench_#{suffix}_#{i}", full_name: "Synthetic #{i}", branch_id: branch.id,
      role_id: role.id, password_digest: digest }
  end
  ids = []
  elapsed = Benchmark.realtime do
    rows.each_slice(1_000) { |batch| ids.concat(User.insert_all!(batch, returning: %w[id]).rows.flatten) }
    ids.each_slice(1_000) do |batch|
      UserDepartment.insert_all!(batch.map { |id| { user_id: id, department_id: department.id, branch_id: branch.id } })
    end
    connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  end
  puts "Bulk insert 10,000 users + 10,000 memberships, indexes and constraints enabled: #{(elapsed * 1_000).round(2)} ms"
  connection.execute("ANALYZE users")
  connection.execute("ANALYZE user_departments")

  queries = {
    login_lookup: User.where(login: rows[9_000][:login]).limit(1),
    keyset_page: User.where(branch_id: branch.id).where("id > ?", ids[8_999]).order(:id).limit(50),
    offset_page: User.where(branch_id: branch.id).order(:id).offset(9_000).limit(50)
  }
  queries.each do |label, relation|
    plan = connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{relation.to_sql}")
    report = JSON.parse(plan).first
    nodes = []
    collect = ->(node) do
      nodes << [ node["Node Type"], node["Index Name"], "rows=#{node['Actual Rows']}" ].compact.join(" ")
      node.fetch("Plans", []).each { |child| collect.call(child) }
    end
    collect.call(report.fetch("Plan"))
    puts "#{label}: #{report['Execution Time']} ms; #{nodes.join(' -> ')}"
  end
  raise ActiveRecord::Rollback
end
