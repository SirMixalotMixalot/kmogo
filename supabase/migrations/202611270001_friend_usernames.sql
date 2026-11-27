begin;

alter table public.roam_profiles add column if not exists username text;
do $$
begin
    if not exists (select 1 from pg_constraint where conrelid = 'public.roam_profiles'::regclass
                   and conname = 'roam_profiles_username_format') then
        alter table public.roam_profiles add constraint roam_profiles_username_format
            check (username is null or username ~ '^[a-z0-9][a-z0-9_]{2,19}$');
    end if;
end;
$$;
create unique index if not exists roam_profiles_username_key on public.roam_profiles(username)
    where username is not null;

-- Existing users choose their own discoverable username; none are generated from email addresses.
create or replace function public.roam_set_username(p_username text)
returns void language plpgsql security definer set search_path = '' as $$
declare
    caller_id uuid := auth.uid();
    requested text := lower(btrim(p_username, E' \t\n\r'));
begin
    if caller_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
    if left(requested, 1) = '@' then requested := substr(requested, 2); end if;
    if requested is null or requested !~ '^[a-z0-9][a-z0-9_]{2,19}$' then
        raise exception 'Invalid username' using errcode = '22023';
    end if;
    update public.roam_profiles set username = requested where user_id = caller_id;
    if not found then raise exception 'Profile unavailable' using errcode = 'P0001'; end if;
end;
$$;

create or replace function public.roam_search_profiles(p_query text)
returns table (user_id uuid, display_name text, username text, friendship_id uuid, status text)
language plpgsql stable security definer set search_path = '' as $$
declare
    caller_id uuid := auth.uid();
    term text := lower(btrim(p_query, E' \t\n\r'));
begin
    if caller_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
    if left(term, 1) = '@' then term := substr(term, 2); end if;
    if term is null or term !~ '^[a-z0-9_]{2,20}$' then return; end if;
    return query
        select p.user_id, p.display_name, p.username, f.id,
            case when f.accepted_at is not null then 'accepted'
                when f.requester_id = caller_id then 'outgoing'
                when f.id is not null then 'incoming' else 'none' end
        from public.roam_profiles p
        left join public.roam_friendships f
            on (f.requester_id = caller_id and f.recipient_id = p.user_id)
            or (f.recipient_id = caller_id and f.requester_id = p.user_id)
        where p.user_id <> caller_id and p.username is not null and starts_with(p.username, term)
        order by p.username limit 20;
end;
$$;

create or replace function public.roam_get_profile(p_username text)
returns table (user_id uuid, display_name text, username text, friendship_id uuid, status text,
               study_seconds bigint, virtual_km double precision)
language plpgsql stable security definer set search_path = '' as $$
declare
    caller_id uuid := auth.uid();
    requested text := lower(btrim(p_username, E' \t\n\r'));
begin
    if caller_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
    if left(requested, 1) = '@' then requested := substr(requested, 2); end if;
    return query
        select p.user_id, p.display_name, p.username, f.id,
            case when p.user_id = caller_id then 'self'
                when f.accepted_at is not null then 'accepted'
                when f.requester_id = caller_id then 'outgoing'
                when f.id is not null then 'incoming' else 'none' end,
            g.study_seconds, g.virtual_km
        from public.roam_profiles p
        left join public.roam_friendships f
            on (f.requester_id = caller_id and f.recipient_id = p.user_id)
            or (f.recipient_id = caller_id and f.requester_id = p.user_id)
        left join public.roam_progress g
            on g.user_id = p.user_id and f.accepted_at is not null and p.share_progress
        where p.username = requested;
end;
$$;

create or replace function public.roam_request_friend_by_username(p_username text)
returns void language plpgsql security definer set search_path = '' as $$
declare
    caller_id uuid := auth.uid();
    requested text := lower(btrim(p_username, E' \t\n\r'));
    target_code uuid;
begin
    if caller_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
    if left(requested, 1) = '@' then requested := substr(requested, 2); end if;
    select p.invite_code into target_code from public.roam_profiles p
        where p.username = requested and p.user_id <> caller_id;
    if target_code is null then raise exception 'Profile unavailable' using errcode = '22023'; end if;
    perform public.roam_request_friend(target_code);
end;
$$;

-- Preserve the old RPC for installed clients; the new client also receives usernames.
create or replace function public.roam_list_friend_profiles()
returns table (friendship_id uuid, friend_id uuid, display_name text, username text, status text,
               study_seconds bigint, virtual_km double precision,
               virtual_latitude double precision, virtual_longitude double precision)
language sql stable security definer set search_path = '' as $$
    with memberships as (
        select f.id, f.accepted_at, f.requester_id = auth.uid() as outgoing,
            case when f.requester_id = auth.uid() then f.recipient_id else f.requester_id end as peer_id
        from public.roam_friendships f where auth.uid() in (f.requester_id, f.recipient_id)
    )
    select m.id, p.user_id, p.display_name, p.username,
        case when m.accepted_at is not null then 'accepted'
            when m.outgoing then 'outgoing' else 'incoming' end,
        g.study_seconds, g.virtual_km, g.virtual_latitude, g.virtual_longitude
    from memberships m join public.roam_profiles p on p.user_id = m.peer_id
    left join public.roam_progress g on g.user_id = p.user_id and m.accepted_at is not null and p.share_progress;
$$;

revoke all on function public.roam_set_username(text), public.roam_search_profiles(text),
    public.roam_get_profile(text), public.roam_request_friend_by_username(text),
    public.roam_list_friend_profiles() from public, anon;
grant execute on function public.roam_set_username(text), public.roam_search_profiles(text),
    public.roam_get_profile(text), public.roam_request_friend_by_username(text),
    public.roam_list_friend_profiles() to authenticated;

notify pgrst, 'reload schema';
commit;
