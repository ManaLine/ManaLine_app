-- OW-007 shipped two buttons that could never work. editAllowedFields and
-- addRemark both raised UnimplementedError because loans has no remarks and
-- no future_effective_information column, and no loan-scoped remarks table
-- existed. An Owner filled either dialog, pressed Save, and got an error --
-- every time, since an empty string is not null.
--
-- Two different things, deliberately shaped differently:
--
--   future_effective_information is ONE editable note about what changes
--   later on this loan. Editing it is the point, so it is a column.
--
--   remarks are an append-only LOG, exactly like customer_remarks, because a
--   lending record that lets somebody overwrite yesterday's note has lost the
--   thing a remark is for. The client's own AG-004 comment already states the
--   rule: "append-only; no edit UI for existing remarks, ever."

alter table loans add column if not exists future_effective_information text;

comment on column loans.future_effective_information is
  'Owner-editable forward-looking note (OW-007 Edit Allowed Fields). Free text, carries no money.';

-- Loan-scoped equivalents of the customer helpers. Neither existed; the
-- customer_remarks policies reach business through customers, and loans
-- carries business_id directly.
create or replace function app.business_id_for_loan(p_loan_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, app
as $$
  select business_id from loans where loan_id = p_loan_id;
$$;

create or replace function app.agent_covers_loan(p_loan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1 from loans l
    where l.loan_id = p_loan_id
      and app.agent_covers_customer(l.customer_id)
  );
$$;

create table if not exists loan_remarks (
  remark_id                uuid primary key default gen_random_uuid(),
  loan_id                  uuid not null references loans(loan_id),
  entered_by_person_id     bigint not null,
  remark_text              text not null,
  priority                 remark_priority_enum not null default 'Normal',
  business_date            date not null default current_date,
  created_at               timestamp not null default now(),
  deleted_at               timestamp,
  deleted_by_membership_id uuid,
  delete_reason            text
);

create index if not exists loan_remarks_loan_id_idx
  on loan_remarks (loan_id, created_at desc);

alter table loan_remarks enable row level security;

drop policy if exists loan_remarks_owner_all on loan_remarks;
create policy loan_remarks_owner_all on loan_remarks
  for all
  using (app.is_owner(app.business_id_for_loan(loan_id)))
  with check (app.is_owner(app.business_id_for_loan(loan_id)));

drop policy if exists loan_remarks_agent_select_assigned on loan_remarks;
create policy loan_remarks_agent_select_assigned on loan_remarks
  for select
  using (
    app.agent_covers_loan(loan_id)
    and app.agent_permission(app.business_id_for_loan(loan_id), 'can_view_customers')
  );

drop policy if exists loan_remarks_agent_insert_assigned on loan_remarks;
create policy loan_remarks_agent_insert_assigned on loan_remarks
  for insert
  with check (
    app.agent_covers_loan(loan_id)
    and app.agent_permission(app.business_id_for_loan(loan_id), 'can_add_remarks')
    and entered_by_person_id = app.current_person_id()
  );

-- Soft delete, same as every other deletable table here: hidden, not gone.
drop policy if exists loan_remarks_hide_deleted on loan_remarks;
create policy loan_remarks_hide_deleted on loan_remarks
  for select
  using (deleted_at is null);
