-- Phase 2 RLS and RPC tests. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

-- Three users. The sign-up trigger creates their profiles.
insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"full_name": "Alice"}', 'authenticated', 'authenticated'),
    ('22222222-2222-2222-2222-222222222222', 'bob@test.local', '{"full_name": "Bob"}', 'authenticated', 'authenticated'),
    ('33333333-3333-3333-3333-333333333333', 'carol@test.local', '{}', 'authenticated', 'authenticated');

select is((select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity), 0,
    'RLS is on for every table in public');
select is((select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Alice',
    'Signing up creates a profile with the Apple name');

-- ---------------------------------------------------------------- Alice creates a group
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok($$ select public.create_group('Morning Crew') $$, 'Alice can create a group');
select is((select role from public.group_members where user_id = '11111111-1111-1111-1111-111111111111'), 'admin',
    'The creator is the group admin');
select set_config('test.group', (select id::text from public.groups limit 1), true);
select set_config('test.code', (select invite_code from public.groups limit 1), true);

-- ---------------------------------------------------------------- Bob, not a member yet
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is((select count(*)::int from public.groups), 0, 'Non-members cannot see a group');
select is((select count(*)::int from public.group_members), 0, 'Non-members cannot see its members');
select is((select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 0,
    'Non-members cannot see each other''s profiles');
select throws_ok($$ select public.join_group('NOPE99') $$, 'P0001', 'invalid_invite_code',
    'join_group with a bad code fails');
select throws_ok(
    $$ insert into public.group_members (group_id, user_id, role)
       values (current_setting('test.group')::uuid, '22222222-2222-2222-2222-222222222222', 'admin') $$,
    '42501', null, 'Clients cannot add themselves to a group directly');

select lives_ok($$ select public.join_group(lower(current_setting('test.code'))) $$,
    'Bob can join with the invite code (any case)');
select lives_ok($$ select public.join_group(current_setting('test.code')) $$, 'Joining twice is a no-op');
select is((select count(*)::int from public.group_members), 2, 'After joining, Bob sees both members');
select is((select role from public.group_members where user_id = '22222222-2222-2222-2222-222222222222'), 'member',
    'People who join are members, not admins');
select is((select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Alice',
    'Group-mates can read each other''s profiles');
select throws_ok($$ select public.rename_group(current_setting('test.group')::uuid, 'Hacked') $$,
    '42501', 'not_group_admin', 'Members cannot rename the group');
select throws_ok($$ select public.regenerate_invite_code(current_setting('test.group')::uuid) $$,
    '42501', 'not_group_admin', 'Members cannot regenerate the invite code');

-- ---------------------------------------------------------------- Profiles
select is_empty($$ update public.profiles set display_name = 'Hacked'
                   where id = '11111111-1111-1111-1111-111111111111' returning id $$,
    'Users cannot update someone else''s profile');
select throws_ok($$ update public.profiles set current_streak = 99
                    where id = '22222222-2222-2222-2222-222222222222' $$,
    '42501', null, 'Users cannot write their own streak');
select lives_ok($$ update public.profiles set display_name = 'Bobby', timezone = 'Europe/London'
                   where id = '22222222-2222-2222-2222-222222222222' $$,
    'Users can change their own name and time zone');
select throws_ok($$ update public.profiles set timezone = 'Mars/Olympus_Mons'
                    where id = '22222222-2222-2222-2222-222222222222' $$,
    '22023', null, 'Unknown time zones are rejected');

-- ---------------------------------------------------------------- Schedules (Alice)
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok($$ select public.save_schedule('[{"weekday": 1, "deadline": "10:00", "lead_minutes": 120}]') $$,
    'Alice can save a schedule');
select is((select count(*)::int from public.habit_schedules), 7,
    'A saved schedule stores all 7 weekdays (the missing ones as rest days)');
select is((select distinct effective_from from public.habit_schedules), (now() at time zone 'UTC')::date + 1,
    'A saved schedule takes effect tomorrow in the user''s time zone');
select throws_ok($$ select public.save_schedule('[{"weekday": 1, "deadline": "00:30", "lead_minutes": 120}]') $$,
    '23514', null, 'Lock windows that cross midnight are rejected');
select throws_ok($$ select public.save_schedule('[{"weekday": 1, "deadline": "10:00", "lead_minutes": 10}]') $$,
    '23514', null, 'Leads under 15 minutes are rejected');

reset role;
select set_config('test.alice_habit',
    (select id::text from public.habits where user_id = '11111111-1111-1111-1111-111111111111'), true);
set local role authenticated;

-- ---------------------------------------------------------------- Bob vs Alice's schedule and scores
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is((select count(*)::int from public.habit_schedules), 0, 'Users cannot read someone else''s schedule');
select throws_ok(
    $$ insert into public.habit_schedules (habit_id, weekday, deadline, lock_lead_minutes, effective_from)
       values (current_setting('test.alice_habit')::uuid, 2, '23:59', 15, current_date) $$,
    '42501', null, 'Users cannot write another user''s schedule');
select throws_ok(
    $$ insert into public.daily_results (user_id, habit_id, local_date, status)
       values ('22222222-2222-2222-2222-222222222222', current_setting('test.alice_habit')::uuid, current_date, 'verified') $$,
    '42501', null, 'Clients cannot write daily results');

-- ---------------------------------------------------------------- Leaving
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select public.leave_group(current_setting('test.group')::uuid);

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select role from public.group_members where user_id = '22222222-2222-2222-2222-222222222222'), 'admin',
    'When the last admin leaves, the longest-standing member becomes admin');

-- ---------------------------------------------------------------- Limits (Carol)
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';

select lives_ok($$ select public.create_group('Group ' || n) from generate_series(1, 5) as n $$,
    'A person can be in 5 groups');
select throws_ok($$ select public.create_group('One too many') $$, 'P0001', 'group_limit_reached',
    'A sixth group is refused');

-- ---------------------------------------------------------------- Signed out
set local role anon;
select is((select count(*)::int from public.profiles), 0, 'Signed-out requests see no profiles');

select * from finish();
rollback;
