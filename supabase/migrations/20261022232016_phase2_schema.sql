-- Phase 2: every table from docs/PLAN.md section 4, with Row Level Security (RLS) on for all of them.
--
-- Rules of thumb used throughout:
--   * Clients (the `authenticated` role) only ever read and write their own data, or read what
--     group-mates are allowed to see. Anything that affects scoring (streaks, daily results, challenges)
--     is written only by Edge Functions using the service role, which bypasses RLS.
--   * Group membership changes go through security-definer RPCs, never direct inserts, so limits and
--     admin rules can't be skipped.
--   * Weekdays are ISO numbers: 1 = Monday … 7 = Sunday (Postgres `extract(isodow …)`).
--     The iOS app converts from Foundation's 1 = Sunday numbering.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text check (char_length(display_name) between 1 and 40),
    timezone text not null default 'UTC',
    current_streak integer not null default 0 check (current_streak >= 0),
    longest_streak integer not null default 0 check (longest_streak >= 0),
    screen_time_ok boolean not null default false,
    created_at timestamptz not null default now()
);

create table public.groups (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 40),
    invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{6,8}$'),
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create table public.group_members (
    group_id uuid not null references public.groups (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    role text not null default 'member' check (role in ('admin', 'member')),
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id)
);
create index group_members_user_id_idx on public.group_members (user_id);

create table public.habits (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    type text not null default 'morning_checkin' check (type in ('morning_checkin')),
    config jsonb not null default '{}'::jsonb,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    unique (user_id, type)
);

-- Versioned: each save inserts a full week (7 rows) with a new effective_from. A rest day is a row with
-- no deadline. The schedule in force on date D is the version with the latest effective_from <= D.
create table public.habit_schedules (
    id uuid primary key default gen_random_uuid(),
    habit_id uuid not null references public.habits (id) on delete cascade,
    weekday smallint not null check (weekday between 1 and 7),
    deadline time,
    lock_lead_minutes integer check (lock_lead_minutes between 15 and 360),
    effective_from date not null,
    created_at timestamptz not null default now(),
    unique (habit_id, effective_from, weekday),
    -- Rest day: both empty. Lock day: both set, and the lock can't start before midnight.
    check ((deadline is null) = (lock_lead_minutes is null)),
    check (deadline is null or extract(epoch from deadline) / 60 >= lock_lead_minutes)
);

create table public.challenges (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    habit_id uuid not null references public.habits (id) on delete cascade,
    local_date date not null,
    target_key text not null,
    target_label text not null,
    hint text,
    opens_at timestamptz not null,
    deadline_at timestamptz not null,
    rerolls_used integer not null default 0 check (rerolls_used between 0 and 1),
    created_at timestamptz not null default now(),
    unique (user_id, habit_id, local_date),
    check (opens_at < deadline_at)
);

create table public.checkins (
    id uuid primary key default gen_random_uuid(),
    challenge_id uuid not null references public.challenges (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    local_date date not null,
    attempt_no integer not null check (attempt_no between 1 and 5),
    status text not null default 'pending' check (status in ('pending', 'verified', 'rejected', 'late')),
    front_path text,
    back_path text,
    phash bigint, -- 64-bit perceptual hash of the back photo; kept after the photos are deleted
    ai_result jsonb,
    rejection_reason text,
    created_at timestamptz not null default now(),
    photos_deleted_at timestamptz,
    unique (challenge_id, attempt_no)
);
create index checkins_user_date_idx on public.checkins (user_id, local_date);

-- Streaks are computed from this table only. Rest days have no row.
create table public.daily_results (
    user_id uuid not null references public.profiles (id) on delete cascade,
    habit_id uuid not null references public.habits (id) on delete cascade,
    local_date date not null,
    status text not null check (status in ('verified', 'missed')),
    late_posted boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (user_id, habit_id, local_date)
);

create table public.device_tokens (
    user_id uuid not null references public.profiles (id) on delete cascade,
    apns_token text not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, apns_token)
);

create table public.coaching_reports (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    week_start date not null,
    summary text not null,
    suggestion text not null,
    created_at timestamptz not null default now(),
    unique (user_id, week_start)
);

create table public.integrity_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    type text not null check (type in ('screen_time_revoked', 'screen_time_restored')),
    created_at timestamptz not null default now()
);
create index integrity_events_user_idx on public.integrity_events (user_id, created_at desc);

-- Service role only: no policies, so clients can't read or write it.
create table public.ai_calls (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references public.profiles (id) on delete set null,
    function text not null,
    model text not null,
    input_tokens integer not null,
    output_tokens integer not null,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.habits enable row level security;
alter table public.habit_schedules enable row level security;
alter table public.challenges enable row level security;
alter table public.checkins enable row level security;
alter table public.daily_results enable row level security;
alter table public.device_tokens enable row level security;
alter table public.coaching_reports enable row level security;
alter table public.integrity_events enable row level security;
alter table public.ai_calls enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers (security definer so policies can check membership without recursing into RLS)
-- ---------------------------------------------------------------------------

create function public.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.group_members
        where group_id = p_group_id and user_id = p_user_id
    );
$$;

create function public.is_group_admin(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.group_members
        where group_id = p_group_id and user_id = p_user_id and role = 'admin'
    );
$$;

create function public.shares_group(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1
        from public.group_members a
        join public.group_members b on b.group_id = a.group_id
        where a.user_id = p_a and b.user_id = p_b
    );
$$;

-- The user's local date "today", from their profile time zone.
create function public.local_today(p_user_id uuid)
returns date
language sql stable security definer set search_path = ''
as $$
    select (now() at time zone coalesce(
        (select timezone from public.profiles where id = p_user_id), 'UTC'))::date;
$$;

-- A random invite code from an alphabet without look-alikes (no 0/O, 1/I/L).
create function public.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    code text;
begin
    loop
        code := '';
        for i in 1..6 loop
            code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
        end loop;
        exit when not exists (select 1 from public.groups where invite_code = code);
    end loop;
    return code;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles: created automatically on sign-up; users edit only their own non-score columns
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name)
    values (new.id, nullif(left(trim(new.raw_user_meta_data ->> 'full_name'), 40), ''));
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

create function public.validate_profile_timezone()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
        raise exception 'unknown time zone: %', new.timezone using errcode = '22023';
    end if;
    return new;
end;
$$;

create trigger profiles_validate_timezone
    before insert or update of timezone on public.profiles
    for each row execute function public.validate_profile_timezone();

create policy "profiles: read own and group-mates"
    on public.profiles for select to authenticated
    using (id = (select auth.uid()) or public.shares_group(id, (select auth.uid())));

create policy "profiles: update own"
    on public.profiles for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- Column-level privileges: clients may change these three columns and nothing else
-- (streak columns are written by Edge Functions only).
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (display_name, timezone, screen_time_ok) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Groups and members: readable by members; changed only through the RPCs below
-- ---------------------------------------------------------------------------

create policy "groups: members read"
    on public.groups for select to authenticated
    using (public.is_group_member(id, (select auth.uid())));

create policy "group_members: members read their groups' members"
    on public.group_members for select to authenticated
    using (public.is_group_member(group_id, (select auth.uid())));

revoke insert, update, delete on public.groups, public.group_members from anon, authenticated;

create function public.create_group(p_name text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
    me constant uuid := auth.uid();
    g public.groups;
begin
    if me is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;
    if (select count(*) from public.group_members where user_id = me) >= 5 then
        raise exception 'group_limit_reached' using errcode = 'P0001', hint = 'You can be in at most 5 groups.';
    end if;
    insert into public.groups (name, invite_code, created_by)
    values (trim(p_name), public.new_invite_code(), me)
    returning * into g;
    insert into public.group_members (group_id, user_id, role) values (g.id, me, 'admin');
    return g;
end;
$$;

create function public.join_group(p_invite_code text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
    me constant uuid := auth.uid();
    g public.groups;
begin
    if me is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;
    select * into g from public.groups where invite_code = upper(trim(p_invite_code));
    if not found then
        raise exception 'invalid_invite_code' using errcode = 'P0001', hint = 'Check the code and try again.';
    end if;
    if public.is_group_member(g.id, me) then
        return g; -- joining twice is a no-op
    end if;
    if (select count(*) from public.group_members where user_id = me) >= 5 then
        raise exception 'group_limit_reached' using errcode = 'P0001', hint = 'You can be in at most 5 groups.';
    end if;
    if (select count(*) from public.group_members where group_id = g.id) >= 20 then
        raise exception 'group_full' using errcode = 'P0001', hint = 'This group already has 20 members.';
    end if;
    insert into public.group_members (group_id, user_id, role) values (g.id, me, 'member');
    return g;
end;
$$;

create function public.leave_group(p_group_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    me constant uuid := auth.uid();
begin
    if not public.is_group_member(p_group_id, me) then
        return;
    end if;
    delete from public.group_members where group_id = p_group_id and user_id = me;
    if not exists (select 1 from public.group_members where group_id = p_group_id) then
        delete from public.groups where id = p_group_id;
    elsif not exists (select 1 from public.group_members where group_id = p_group_id and role = 'admin') then
        -- The last admin left: the longest-standing member takes over.
        update public.group_members set role = 'admin'
        where (group_id, user_id) = (
            select group_id, user_id from public.group_members
            where group_id = p_group_id order by joined_at, user_id limit 1
        );
    end if;
end;
$$;

create function public.rename_group(p_group_id uuid, p_name text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
    g public.groups;
begin
    if not public.is_group_admin(p_group_id, auth.uid()) then
        raise exception 'not_group_admin' using errcode = '42501';
    end if;
    update public.groups set name = trim(p_name) where id = p_group_id returning * into g;
    return g;
end;
$$;

create function public.regenerate_invite_code(p_group_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    code text;
begin
    if not public.is_group_admin(p_group_id, auth.uid()) then
        raise exception 'not_group_admin' using errcode = '42501';
    end if;
    code := public.new_invite_code();
    update public.groups set invite_code = code where id = p_group_id;
    return code;
end;
$$;

create function public.remove_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
    if not public.is_group_admin(p_group_id, auth.uid()) then
        raise exception 'not_group_admin' using errcode = '42501';
    end if;
    if p_user_id = auth.uid() then
        raise exception 'use leave_group to leave' using errcode = 'P0001';
    end if;
    delete from public.group_members where group_id = p_group_id and user_id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Habits and schedules: own rows only; schedules are saved through save_schedule
-- ---------------------------------------------------------------------------

create policy "habits: read own"
    on public.habits for select to authenticated
    using (user_id = (select auth.uid()));

create policy "habit_schedules: read own"
    on public.habit_schedules for select to authenticated
    using (exists (
        select 1 from public.habits h
        where h.id = habit_id and h.user_id = (select auth.uid())
    ));

revoke insert, update, delete on public.habits, public.habit_schedules from anon, authenticated;

-- Saves a full week as a new version that takes effect tomorrow (in the user's time zone), so a
-- deadline can't be moved to 23:59 on the day it's due. Saving twice in a day replaces the pending
-- version. p_days: [{"weekday": 1-7, "deadline": "HH:MM", "lead_minutes": 15-360}, …]; weekdays left
-- out are rest days. Returns the date the new schedule takes effect.
create function public.save_schedule(p_days jsonb)
returns date
language plpgsql security definer set search_path = ''
as $$
declare
    me constant uuid := auth.uid();
    habit uuid;
    starts date;
    day jsonb;
    seen smallint[] := '{}';
    wd smallint;
begin
    if me is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;
    if jsonb_typeof(p_days) <> 'array' then
        raise exception 'p_days must be a JSON array' using errcode = '22023';
    end if;

    insert into public.habits (user_id, type) values (me, 'morning_checkin')
    on conflict (user_id, type) do nothing;
    select id into habit from public.habits where user_id = me and type = 'morning_checkin';

    starts := public.local_today(me) + 1;
    delete from public.habit_schedules where habit_id = habit and effective_from = starts;

    for day in select * from jsonb_array_elements(p_days) loop
        wd := (day ->> 'weekday')::smallint;
        if wd is null or wd not between 1 and 7 or wd = any(seen) then
            raise exception 'invalid or repeated weekday: %', day ->> 'weekday' using errcode = '22023';
        end if;
        seen := seen || wd;
        insert into public.habit_schedules (habit_id, weekday, deadline, lock_lead_minutes, effective_from)
        values (habit, wd, (day ->> 'deadline')::time, (day ->> 'lead_minutes')::integer, starts);
    end loop;

    -- Every weekday not listed is stored as an explicit rest day, so it overrides older versions.
    insert into public.habit_schedules (habit_id, weekday, deadline, lock_lead_minutes, effective_from)
    select habit, d, null, null, starts
    from generate_series(1, 7) as d
    where d::smallint <> all(seen);

    return starts;
end;
$$;

-- The schedule row in force for a user's habit on a given date (null deadline = rest day).
create function public.schedule_for(p_habit_id uuid, p_date date)
returns public.habit_schedules
language sql stable security definer set search_path = ''
as $$
    select s.* from public.habit_schedules s
    where s.habit_id = p_habit_id
      and s.weekday = extract(isodow from p_date)
      and s.effective_from <= p_date
    order by s.effective_from desc
    limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Scoring and feed tables: read-only for clients for now. Phases 3–6 add the write paths
-- (Edge Functions with the service role) and the friends' no-peeking feed policy.
-- ---------------------------------------------------------------------------

create policy "challenges: read own"
    on public.challenges for select to authenticated
    using (user_id = (select auth.uid()));

create policy "checkins: read own"
    on public.checkins for select to authenticated
    using (user_id = (select auth.uid()));

create policy "daily_results: read own and group-mates"
    on public.daily_results for select to authenticated
    using (user_id = (select auth.uid()) or public.shares_group(user_id, (select auth.uid())));

create policy "coaching_reports: read own"
    on public.coaching_reports for select to authenticated
    using (user_id = (select auth.uid()));

create policy "integrity_events: read own and group-mates"
    on public.integrity_events for select to authenticated
    using (user_id = (select auth.uid()) or public.shares_group(user_id, (select auth.uid())));

create policy "device_tokens: manage own"
    on public.device_tokens for all to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

revoke insert, update, delete on public.challenges, public.checkins, public.daily_results,
    public.coaching_reports, public.integrity_events, public.ai_calls from anon, authenticated;
revoke all on public.ai_calls from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Function privileges: RPCs for signed-in users only; helpers not callable from the API
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

grant execute on function
    public.create_group(text),
    public.join_group(text),
    public.leave_group(uuid),
    public.rename_group(uuid, text),
    public.regenerate_invite_code(uuid),
    public.remove_member(uuid, uuid),
    public.save_schedule(jsonb)
to authenticated;

-- Used inside RLS policies, which run as the querying role.
grant execute on function
    public.is_group_member(uuid, uuid),
    public.shares_group(uuid, uuid)
to authenticated;
