-- Run after the migration in a privileged SQL session. All fixtures and changes roll back.
begin;
do $$
begin
    if exists (select 1 from auth.users where id in (
        '10000000-0000-4000-8000-000000000001'::uuid,
        '10000000-0000-4000-8000-000000000002'::uuid,
        '10000000-0000-4000-8000-000000000003'::uuid)) then
        raise exception 'Fixture IDs are already occupied; no fixtures were changed';
    end if;
end;
$$;
insert into auth.users(id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
    ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'roam-test-a@example.invalid', '{}', '{}', now(), now()),
    ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'roam-test-b@example.invalid', '{}', '{}', now(), now()),
    ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'roam-test-c@example.invalid', '{}', '{}', now(), now());
insert into public.roam_profiles(user_id, display_name) values
    ('10000000-0000-4000-8000-000000000001', 'Test Alice'),
    ('10000000-0000-4000-8000-000000000002', 'Test Bob'),
    ('10000000-0000-4000-8000-000000000003', 'Test Cara');
insert into public.roam_progress(user_id, study_seconds, virtual_km, virtual_latitude, virtual_longitude) values
    ('10000000-0000-4000-8000-000000000002', 3600, 12, 43.5, -80.5);

do $$
declare
    alice uuid := '10000000-0000-4000-8000-000000000001';
    bob uuid := '10000000-0000-4000-8000-000000000002';
    cara uuid := '10000000-0000-4000-8000-000000000003';
    link_id uuid;
    row_data record;
    denied boolean;
begin
    if has_function_privilege('anon', 'public.roam_search_profiles(text)', 'execute')
       or has_function_privilege('anon', 'public.roam_get_profile(text)', 'execute')
       or has_function_privilege('anon', 'public.roam_set_username(text)', 'execute')
       or has_function_privilege('anon', 'public.roam_request_friend_by_username(text)', 'execute') then
        raise exception 'Anonymous profile access is enabled';
    end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', alice::text, true);
    perform public.roam_set_username(' @ZZT27_ALICE ');
    if (select p.username from public.roam_profiles p where p.user_id = alice) <> 'zzt27_alice' then
        raise exception 'Username was not normalized';
    end if;
    denied := false;
    begin perform public.roam_set_username('bad/name');
    exception when invalid_parameter_value then denied := true; end;
    if not denied then raise exception 'Invalid username accepted'; end if;

    perform set_config('request.jwt.claim.sub', bob::text, true);
    perform public.roam_set_username('zzt27_bob');
    denied := false;
    begin perform public.roam_set_username('ZZT27_ALICE');
    exception when unique_violation then denied := true; end;
    if not denied then raise exception 'Duplicate username accepted'; end if;
    update public.roam_profiles set share_progress = true where user_id = bob;
    perform set_config('request.jwt.claim.sub', cara::text, true);
    perform public.roam_set_username('zzt27_cara');

    perform set_config('request.jwt.claim.sub', alice::text, true);
    if (select count(*) from public.roam_search_profiles('@ZZT27_') p where p.user_id in (bob, cara)) <> 2 then
        raise exception 'Username prefix search failed';
    end if;
    if exists (select 1 from public.roam_search_profiles('zzt27') p where p.user_id = alice) then
        raise exception 'Search returned the current user';
    end if;
    if exists (select 1 from public.roam_search_profiles('z%') p) then
        raise exception 'Search accepted a wildcard query';
    end if;
    select * into row_data from public.roam_get_profile('zzt27_bob');
    if row_data.status <> 'none' or row_data.study_seconds is not null then
        raise exception 'Non-friend could see progress';
    end if;
    if to_jsonb(row_data) ? 'email' or to_jsonb(row_data) ? 'invite_code' then
        raise exception 'Profile exposed private account fields';
    end if;
    denied := false;
    begin perform public.roam_request_friend_by_username('zzt27_alice');
    exception when invalid_parameter_value then denied := true; end;
    if not denied then raise exception 'Self friend request accepted'; end if;
    perform public.roam_request_friend_by_username('zzt27_bob');
    perform public.roam_request_friend_by_username('zzt27_bob');
    select * into row_data from public.roam_get_profile('zzt27_bob');
    link_id := row_data.friendship_id;
    if row_data.status <> 'outgoing' or link_id is null or row_data.study_seconds is not null then
        raise exception 'Outgoing request state or privacy is wrong';
    end if;
    if public.roam_accept_friend(link_id) then raise exception 'Requester accepted their own request'; end if;
    perform set_config('request.jwt.claim.sub', bob::text, true);
    select * into row_data from public.roam_get_profile('zzt27_alice');
    if row_data.status <> 'incoming' then raise exception 'Incoming request state is wrong'; end if;
    if not public.roam_accept_friend(link_id) then raise exception 'Recipient could not accept'; end if;

    perform set_config('request.jwt.claim.sub', alice::text, true);
    select * into row_data from public.roam_get_profile('zzt27_bob');
    if row_data.status <> 'accepted' or row_data.study_seconds <> 3600 or row_data.virtual_km <> 12 then
        raise exception 'Accepted friend cannot see opted-in progress';
    end if;
    if not exists (select 1 from public.roam_list_friend_profiles() p
                   where p.friend_id = bob and p.username = 'zzt27_bob' and p.virtual_latitude = 43.5) then
        raise exception 'Friend map profile lost its username or virtual position';
    end if;
    perform set_config('request.jwt.claim.sub', cara::text, true);
    select * into row_data from public.roam_get_profile('zzt27_bob');
    if row_data.study_seconds is not null then raise exception 'Unrelated user could see progress'; end if;
    perform set_config('request.jwt.claim.sub', bob::text, true);
    update public.roam_profiles set share_progress = false where user_id = bob;
    perform public.roam_set_username('zzt27_bob_new');
    perform set_config('request.jwt.claim.sub', alice::text, true);
    select * into row_data from public.roam_get_profile('zzt27_bob_new');
    if row_data.status <> 'accepted' or row_data.study_seconds is not null then
        raise exception 'Disabling sharing or changing a username broke privacy/friendship';
    end if;
    if exists (select 1 from public.roam_get_profile('zzt27_bob')) then
        raise exception 'Old username still resolves';
    end if;
    if not public.roam_remove_friend(link_id) then raise exception 'Friend removal failed'; end if;
    select * into row_data from public.roam_get_profile('zzt27_bob_new');
    if row_data.status <> 'none' then raise exception 'Removed friendship is still visible'; end if;
    execute 'reset role';
end;
$$;
rollback;
select 'PASS: username uniqueness/search, profile privacy, requests, acceptance, rename, and removal; all fixtures rolled back' as result;
