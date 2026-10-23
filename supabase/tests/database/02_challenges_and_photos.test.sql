-- Phase 3: challenge windows and the private photo bucket. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email, aud, role) values
    ('11111111-1111-1111-1111-111111111111', 'alice@test.local', 'authenticated', 'authenticated'),
    ('22222222-2222-2222-2222-222222222222', 'bob@test.local', 'authenticated', 'authenticated');
update public.profiles set timezone = 'Europe/London' where id = '11111111-1111-1111-1111-111111111111';

-- Alice: every day 10:00 deadline, 2 h lead, except Sunday (ISO 7), which is a rest day.
insert into public.habits (id, user_id) values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');
insert into public.habit_schedules (habit_id, weekday, deadline, lock_lead_minutes, effective_from)
select 'aaaaaaaa-0000-0000-0000-000000000001', d,
       case when d = 7 then null else time '10:00' end,
       case when d = 7 then null else 120 end,
       date '2026-01-01'
from generate_series(1, 7) as d;

-- ---------------------------------------------------------------- Windows in the user's time zone
-- Friday 23 Oct 2026 is British Summer Time (UTC+1); Monday 26 Oct is after the clocks go back (UTC+0).
select is((select opens_at from public.challenge_window('11111111-1111-1111-1111-111111111111', date '2026-10-23')),
    timestamptz '2026-10-23 07:00:00+00', 'Lock opens at 08:00 London time in summer time');
select is((select deadline_at from public.challenge_window('11111111-1111-1111-1111-111111111111', date '2026-10-23')),
    timestamptz '2026-10-23 09:00:00+00', 'Deadline is 10:00 London time in summer time');
select is((select opens_at from public.challenge_window('11111111-1111-1111-1111-111111111111', date '2026-10-26')),
    timestamptz '2026-10-26 08:00:00+00', 'Lock opens at 08:00 London time after the clocks go back');
select is_empty($$ select * from public.challenge_window('11111111-1111-1111-1111-111111111111', date '2026-10-25') $$,
    'No window on a rest day');
select is_empty($$ select * from public.challenge_window('22222222-2222-2222-2222-222222222222', date '2026-10-23') $$,
    'No window without a schedule');

-- ---------------------------------------------------------------- ensure_challenge (today, whatever day that is)
update public.habit_schedules set deadline = '10:00', lock_lead_minutes = 120 where weekday = 7;
select is((select count(*)::int from public.ensure_challenge('11111111-1111-1111-1111-111111111111', 'bench', 'a bench', 'Parks and bus stops')),
    1, 'ensure_challenge creates today''s challenge');
select is((select target_key from public.ensure_challenge('11111111-1111-1111-1111-111111111111', 'tree', 'a tree', null)),
    'bench', 'Calling it again keeps the first target');

-- ---------------------------------------------------------------- Access rules
set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select throws_ok($$ select * from public.ensure_challenge('22222222-2222-2222-2222-222222222222', 'bench', 'a bench', null) $$,
    '42501', null, 'Clients cannot create challenges');
select throws_ok(
    $$ insert into storage.objects (bucket_id, name) values ('checkins', '11111111-1111-1111-1111-111111111111/2026-10-23/x_front.jpg') $$,
    '42501', null, 'Users cannot upload into someone else''s photo folder');
select lives_ok(
    $$ insert into storage.objects (bucket_id, name) values ('checkins', '22222222-2222-2222-2222-222222222222/2026-10-23/x_front.jpg') $$,
    'Users can upload into their own photo folder');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is_empty($$ select name from storage.objects where bucket_id = 'checkins' $$,
    'Users cannot see someone else''s photos (no-peeking arrives in Phase 5)');

select * from finish();
rollback;
