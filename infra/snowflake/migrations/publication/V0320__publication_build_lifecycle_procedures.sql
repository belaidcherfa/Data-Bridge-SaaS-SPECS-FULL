-- contract=snowflake-publication-build-lifecycle version=1 status=DRAFT owner_task=ORC-005 decisions=D-05,D-06 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.PUBLICATION.
-- Owner's-rights procedures implementing contracts/state-machines/build.yaml transitions that are not produced by
-- PREPARE_CANDIDATES (V0321) or PUBLISH_BATCH (V0322):
--   ACQUIRE_LANE_FENCE(lane, fence_token, build_id)            PLANNED -> RUNNING; older non-terminal builds of the lane -> FENCED
--   TRANSITION_BUILD(build_id, fence_token, to_status, error_class, error_code)
--                                                              RUNNING -> BUILT | FAILED | CANCELLED | ABANDONED | SIMULATED,
--                                                              PLANNED -> CANCELLED, BUILT/VALIDATED -> CANCELLED | ABANDONED | FAILED
-- Every call is one DML-only transaction. The caller (Dagster dbt/intelligence code location, role BRIDGE_PUBLISHER)
-- must not have an open transaction (autocommit session); the fence token is the PostgreSQL lane-lease fencing token.
-- Return value: VARIANT object {"code": ..., ...}; unexpected errors roll back and re-raise.
-- TO VERIFY LIVE (ORC-005-S04): explicit transactions inside EXECUTE AS OWNER procedures and SQLROWCOUNT after UPDATE ... FROM.

create or replace procedure bridge.publication.acquire_lane_fence(
    p_lane varchar, p_fence_token number(38,0), p_build_id varchar)
returns variant
language sql
execute as owner
comment = 'K4/ORC-005-S12: acquire the Snowflake lane fence with a strictly larger PostgreSQL lease token; fences zombies'
as
$$
declare
    v_now          timestamp_ntz(9);
    v_rows         number(38,0);
    v_cur_token    number(38,0);
    v_cur_build    varchar;
    v_build_fence  number(38,0);
    v_build_lane   varchar;
    v_build_status varchar;
    v_fenced       number(38,0);
begin
    v_now := sysdate();
    begin transaction;

    select count(*) into :v_rows from bridge.publication.build where build_id = :p_build_id;
    if (v_rows = 0) then
        rollback;
        return object_construct('code', 'BUILD_NOT_FOUND', 'build_id', p_build_id);
    end if;
    select fence_token, lane, status into :v_build_fence, :v_build_lane, :v_build_status
      from bridge.publication.build where build_id = :p_build_id;
    if (v_build_fence <> p_fence_token or v_build_lane <> p_lane) then
        rollback;
        return object_construct('code', 'FENCE_MISMATCH', 'build_id', p_build_id, 'build_fence_token', v_build_fence, 'lane', v_build_lane);
    end if;

    update bridge.publication.lane_fence
       set fence_token = :p_fence_token, build_id = :p_build_id, acquired_at = :v_now, updated_at = :v_now
     where lane = :p_lane and fence_token < :p_fence_token;
    v_rows := sqlrowcount;
    if (v_rows = 0) then
        select fence_token, build_id into :v_cur_token, :v_cur_build from bridge.publication.lane_fence where lane = :p_lane;
        rollback;
        if (v_cur_token = p_fence_token and v_cur_build = p_build_id) then
            return object_construct('code', 'ALREADY_HELD', 'lane', p_lane, 'fence_token', p_fence_token, 'build_id', p_build_id, 'build_status', v_build_status);
        end if;
        return object_construct('code', 'FENCED', 'lane', p_lane, 'current_fence_token', v_cur_token, 'current_build_id', v_cur_build);
    end if;

    -- Zombies: every older non-terminal build of the lane can no longer publish.
    update bridge.publication.build
       set status = 'FENCED', error_code = 'ORC_BUILD_FENCED', ended_at = :v_now, status_changed_at = :v_now
     where lane = :p_lane and build_id <> :p_build_id and fence_token < :p_fence_token
       and status in ('PLANNED', 'RUNNING', 'BUILT', 'VALIDATED');
    v_fenced := sqlrowcount;

    -- Their batches become plannable again (BATCH_PROCESSING lifecycle).
    update bridge.ops_meta.batch_processing
       set status = 'PENDING', last_status_at = :v_now
     where status in ('IN_BUILD', 'BUILT')
       and build_id in (select build_id from bridge.publication.build
                         where lane = :p_lane and status = 'FENCED' and fence_token < :p_fence_token);

    update bridge.publication.build
       set status = 'RUNNING', started_at = :v_now, status_changed_at = :v_now
     where build_id = :p_build_id and status = 'PLANNED' and fence_token = :p_fence_token;
    if (sqlrowcount <> 1) then
        rollback;
        return object_construct('code', 'NOT_PLANNED', 'build_id', p_build_id, 'build_status', v_build_status);
    end if;

    commit;
    return object_construct('code', 'ACQUIRED', 'lane', p_lane, 'fence_token', p_fence_token, 'build_id', p_build_id, 'builds_fenced', v_fenced);
exception
    when other then
        rollback;
        raise;
end;
$$;

create or replace procedure bridge.publication.transition_build(
    p_build_id varchar, p_fence_token number(38,0), p_to_status varchar, p_error_class varchar, p_error_code varchar)
returns variant
language sql
execute as owner
comment = 'K4/ORC-005, ORC-006: compare-and-swap build status transitions with processing-ledger side effects'
as
$$
declare
    v_now          timestamp_ntz(9);
    v_rows         number(38,0);
    v_status       varchar;
    v_lane         varchar;
    v_kind         varchar;
    v_build_fence  number(38,0);
    v_lane_fence   number(38,0);
begin
    v_now := sysdate();
    if (p_to_status not in ('BUILT', 'FAILED', 'CANCELLED', 'ABANDONED', 'SIMULATED')) then
        return object_construct('code', 'TRANSITION_NOT_ALLOWED', 'to_status', p_to_status);
    end if;

    begin transaction;
    select count(*) into :v_rows from bridge.publication.build where build_id = :p_build_id;
    if (v_rows = 0) then
        rollback;
        return object_construct('code', 'BUILD_NOT_FOUND', 'build_id', p_build_id);
    end if;
    select status, lane, kind, fence_token into :v_status, :v_lane, :v_kind, :v_build_fence
      from bridge.publication.build where build_id = :p_build_id;
    select fence_token into :v_lane_fence from bridge.publication.lane_fence where lane = :v_lane;

    if (v_build_fence <> p_fence_token) then
        rollback;
        return object_construct('code', 'FENCED', 'build_id', p_build_id, 'build_fence_token', v_build_fence);
    end if;
    -- Progress transitions require holding the lane; stop transitions (cancel, worker lost) do not.
    if (p_to_status in ('BUILT', 'FAILED', 'SIMULATED') and v_lane_fence <> p_fence_token) then
        rollback;
        return object_construct('code', 'FENCED', 'build_id', p_build_id, 'lane_fence_token', v_lane_fence);
    end if;
    if (p_to_status = 'SIMULATED' and v_kind <> 'SIMULATION') then
        rollback;
        return object_construct('code', 'TRANSITION_NOT_ALLOWED', 'from_status', v_status, 'to_status', p_to_status, 'kind', v_kind);
    end if;

    update bridge.publication.build
       set status = :p_to_status,
           error_class = :p_error_class,
           error_code = :p_error_code,
           built_at = iff(:p_to_status = 'BUILT', :v_now, built_at),
           ended_at = iff(:p_to_status = 'BUILT', ended_at, :v_now),
           status_changed_at = :v_now
     where build_id = :p_build_id and fence_token = :p_fence_token
       and (   (:p_to_status in ('BUILT', 'SIMULATED') and status = 'RUNNING')
            or (:p_to_status = 'FAILED'    and status in ('RUNNING', 'BUILT', 'VALIDATED'))
            or (:p_to_status = 'CANCELLED' and status in ('PLANNED', 'RUNNING', 'BUILT', 'VALIDATED'))
            or (:p_to_status = 'ABANDONED' and status in ('RUNNING', 'BUILT', 'VALIDATED')));
    if (sqlrowcount <> 1) then
        rollback;
        return object_construct('code', 'TRANSITION_NOT_ALLOWED', 'from_status', v_status, 'to_status', p_to_status);
    end if;

    if (p_to_status = 'BUILT') then
        update bridge.ops_meta.batch_processing
           set status = 'BUILT', last_status_at = :v_now
         where build_id = :p_build_id and status = 'IN_BUILD';
    elseif (p_to_status in ('FAILED', 'CANCELLED', 'ABANDONED')) then
        update bridge.ops_meta.batch_processing
           set status = 'PENDING', last_status_at = :v_now
         where build_id = :p_build_id and status in ('IN_BUILD', 'BUILT');
    end if;

    commit;
    return object_construct('code', 'TRANSITIONED', 'build_id', p_build_id, 'from_status', v_status, 'to_status', p_to_status);
exception
    when other then
        rollback;
        raise;
end;
$$;
