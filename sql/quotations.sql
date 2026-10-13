-- AVCHS portal: Quotations tab
-- Run once in Supabase → SQL Editor (project hnnuldiybhzdkvvtpxeu). Safe to re-run.

create table if not exists public.quotations (
  id            bigint generated always as identity primary key,
  category      text   not null default 'other',
  job_title     text   not null,
  vendor_name   text   not null,
  vendor_phone  text,
  quote_date    date,
  valid_till    date,
  amount        numeric(14,2) check (amount is null or amount >= 0),
  gst_included  boolean not null default false,
  status        text   not null default 'received'
                check (status in ('received','shortlisted','approved','rejected')),
  visibility    text   not null default 'members'
                check (visibility in ('members','admins')),
  notes         text,
  storage_path  text,
  file_name     text,
  created_by    uuid   default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists quotations_job_idx on public.quotations (category, job_title);

alter table public.quotations enable row level security;

-- Committee = chairman / secretary / treasurer (same roles the website treats as admins)
drop policy if exists quotations_read  on public.quotations;
drop policy if exists quotations_write on public.quotations;

create policy quotations_read on public.quotations for select to authenticated using (
  visibility = 'members'
  or exists (select 1 from public.profiles p where p.id = auth.uid()
             and p.role in ('chairman','secretary','treasurer'))
);

create policy quotations_write on public.quotations for all to authenticated
  using      (exists (select 1 from public.profiles p where p.id = auth.uid()
                      and p.role in ('chairman','secretary','treasurer')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid()
                      and p.role in ('chairman','secretary','treasurer')));

grant select, insert, update, delete on public.quotations to authenticated;

-- Record every change in the Activity log, using the same trigger the Notices table already uses
do $$
declare fn text;
begin
  select t.tgfoid::regproc::text into fn
  from pg_trigger t
  where t.tgrelid = 'public.notices'::regclass and not t.tgisinternal
  limit 1;
  if fn is not null then
    execute 'drop trigger if exists quotations_audit on public.quotations';
    execute format('create trigger quotations_audit after insert or update or delete on public.quotations
                    for each row execute function %s()', fn);
    raise notice 'Activity log trigger attached using %', fn;
  else
    raise notice 'No audit trigger found on notices; quotations will not appear in the Activity log';
  end if;
end $$;
