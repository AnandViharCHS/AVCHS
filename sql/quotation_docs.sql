-- AVCHS portal: Tax invoices & receipts attached to quotations
-- Run once in Supabase → SQL Editor (project hnnuldiybhzdkvvtpxeu), after quotations.sql. Safe to re-run.

create table if not exists public.quotation_docs (
  id            bigint generated always as identity primary key,
  quotation_id  bigint not null references public.quotations(id) on delete cascade,
  doc_type      text   not null check (doc_type in ('invoice','receipt')),
  doc_no        text,
  doc_date      date,
  amount        numeric(14,2) check (amount is null or amount >= 0),
  payment_mode  text,
  payment_ref   text,   -- cheque / UTR no. for receipts, vendor GSTIN for invoices
  storage_path  text,
  file_name     text,
  created_by    uuid   default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now()
);
create index if not exists quotation_docs_q_idx on public.quotation_docs (quotation_id);

alter table public.quotation_docs enable row level security;

drop policy if exists quotation_docs_read  on public.quotation_docs;
drop policy if exists quotation_docs_write on public.quotation_docs;

-- Members see invoices/receipts only for quotations they are allowed to see
create policy quotation_docs_read on public.quotation_docs for select to authenticated using (
  exists (select 1 from public.quotations q where q.id = quotation_id)
);

create policy quotation_docs_write on public.quotation_docs for all to authenticated
  using      (exists (select 1 from public.profiles p where p.id = auth.uid()
                      and p.role in ('chairman','secretary','treasurer')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid()
                      and p.role in ('chairman','secretary','treasurer')));

grant select, insert, update, delete on public.quotation_docs to authenticated;

-- Activity log: reuse the trigger already used on the Notices table
do $$
declare fn text;
begin
  select t.tgfoid::regproc::text into fn
  from pg_trigger t
  where t.tgrelid = 'public.notices'::regclass and not t.tgisinternal
  limit 1;
  if fn is not null then
    execute 'drop trigger if exists quotation_docs_audit on public.quotation_docs';
    execute format('create trigger quotation_docs_audit after insert or update or delete on public.quotation_docs
                    for each row execute function %s()', fn);
  end if;
end $$;
