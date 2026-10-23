-- Phase 3: photo storage and today's challenge window.
--
-- Check-in rows are written only by the verify-checkin Edge Function (service role), which counts
-- attempts and checks the time window. Clients only upload the two photos.

-- ---------------------------------------------------------------------------
-- Private bucket: {user_id}/{local_date}/{checkin_id}_{front|back}.jpg
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('checkins', 'checkins', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- Uploads only into your own folder. No update or delete for clients, so photos can't be swapped
-- after a check-in is verified. Friends' read access (no-peeking rule) arrives in Phase 5.
create policy "checkins bucket: upload to own folder"
    on storage.objects for insert to authenticated
    with check (bucket_id = 'checkins' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "checkins bucket: read own photos"
    on storage.objects for select to authenticated
    using (bucket_id = 'checkins' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- Today's challenge, created on demand by the issue-challenge Edge Function
-- ---------------------------------------------------------------------------

-- The lock window for a user on their local date, as absolute timestamps. Null on a rest day.
create function public.challenge_window(p_user_id uuid, p_local_date date)
returns table (habit_id uuid, opens_at timestamptz, deadline_at timestamptz)
language sql stable security definer set search_path = ''
as $$
    select h.id,
           ((p_local_date + s.deadline - make_interval(mins => s.lock_lead_minutes))::timestamp
               at time zone p.timezone),
           ((p_local_date + s.deadline)::timestamp at time zone p.timezone)
    from public.profiles p
    join public.habits h on h.user_id = p.id and h.type = 'morning_checkin' and h.active
    cross join lateral public.schedule_for(h.id, p_local_date) s
    where p.id = p_user_id and s.deadline is not null;
$$;

-- Returns today's challenge for the user, creating it with the given target if it doesn't exist yet.
-- Returns no row on a rest day or without a schedule.
create function public.ensure_challenge(p_user_id uuid, p_target_key text, p_target_label text, p_hint text)
returns setof public.challenges
language plpgsql volatile security definer set search_path = ''
as $$
declare
    today date := public.local_today(p_user_id);
    w record;
begin
    select * into w from public.challenge_window(p_user_id, today);
    if not found then
        return;
    end if;
    insert into public.challenges (user_id, habit_id, local_date, target_key, target_label, hint, opens_at, deadline_at)
    values (p_user_id, w.habit_id, today, p_target_key, p_target_label, p_hint, w.opens_at, w.deadline_at)
    on conflict (user_id, habit_id, local_date) do nothing;
    return query
        select * from public.challenges c
        where c.user_id = p_user_id and c.habit_id = w.habit_id and c.local_date = today;
end;
$$;

-- Service role only (Edge Functions).
revoke execute on function public.challenge_window(uuid, date) from public, anon, authenticated;
revoke execute on function public.ensure_challenge(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.challenge_window(uuid, date) to service_role;
grant execute on function public.ensure_challenge(uuid, text, text, text) to service_role;
