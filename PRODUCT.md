# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Confirmed from `docs/hr_emirmed_specification_v0_1.md`: recruiters manage their requisitions and campaigns; HR leadership maintains vacancy templates and shared recruitment oversight; department managers participate in requisitions and later interview or internship stages. Access depends on role permissions, assignment, and organizational scope.

Assumption for this UI implementation, because the optional questions received no answer: the primary daily user is a recruiter working through a queue of candidate records and recruitment requests in an office setting.

## Product Purpose

The system supports recruitment for HR Emirmed: candidate records and resumes, vacancy templates, job requisitions, recruitment campaigns, and candidate applications. Success means staff can move candidates through authorized hiring work while preserving ownership, history, and the conditions that applied to each application.

## Positioning

The product connects candidate records to versioned recruitment requests and campaigns, while keeping each application’s stages, decisions, and access tied to its responsible staff and permissions.

## Operating Context

Recruiters search resumes, review candidate records, work on requisitions and campaigns, and make application decisions. HR leadership maintains templates, rejection reasons, duplicate resolution, and organization-wide oversight. Department managers create and track their requests and participate when candidates are assigned to their interview or internship stages.

Assumption for the initial web surface: a compact daily work area with a list as its first screen; users move from searchable registers into candidate, template, requisition, and campaign details.

## Capabilities and Constraints

- Employees sign in with an account created by an administrator.
- The product includes candidate records with multiple resumes, contacts, sources, and application history.
- Vacancy templates and requisitions preserve versions of hiring conditions.
- Campaigns can require approval and can be launched, paused, or resumed through authorized actions.
- Applications progress through screening, test review, interview, internship, and offer stages. Completion records an explicit outcome and whether another application may be proposed.
- Permissions and assignment determine which records and actions a user can access. Seeing a candidate record does not imply access to that candidate’s other applications.
- Candidate imports must not start outreach or tests. Integrations and external messaging availability remain undecided in the specification.
- The existing project is a Rails web application. The web interface uses server-rendered views and Hotwire/Turbo for in-place list updates.
- The specification leaves several workflow details open, including integration capabilities, reminders, test rules, pause behavior, and detailed access policy. The interface must not present those as settled facts.

## Evidence on Hand

`docs/hr_emirmed_specification_v0_1.md` contains proposed workflows, roles, constraints, and acceptance scenarios. It labels some details as proposals and lists unresolved decisions. There are no approved customer testimonials, operational metrics, or brand assets in the current interface scope; do not invent them.

## Product Principles

- Show only actions authorized for the current user and record.
- Keep candidate identity, applications, and versioned hiring conditions distinct.
- Make ownership, stage, and decision history clear.
- Preserve explicit human decisions where the specification requires them.
- Treat unresolved workflow details as open rather than silently turning them into policy.

## Accessibility & Inclusion

Use explicit labels, visible validation messages, keyboard-accessible controls, and responsive layouts. Candidate communication language is stored as a candidate preference; do not assume a single language for candidates.
