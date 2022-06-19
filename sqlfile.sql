--
-- PostgreSQL database dump
--

-- Dumped from database version 14.3 (Ubuntu 14.3-1.pgdg20.04+1)
-- Dumped by pg_dump version 14.3 (Ubuntu 14.3-1.pgdg20.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA topology;


ALTER SCHEMA topology OWNER TO postgres;

--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: contacts_contact; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contact (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(128),
    language character varying(3),
    fields jsonb,
    status character varying(1) NOT NULL,
    ticket_count integer NOT NULL,
    last_seen_on timestamp with time zone,
    created_by_id integer,
    current_flow_id integer,
    modified_by_id integer,
    org_id integer NOT NULL
);


ALTER TABLE public.contacts_contact OWNER TO flowartisan;

--
-- Name: contact_toggle_system_group(public.contacts_contact, character, boolean); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.contact_toggle_system_group(_contact public.contacts_contact, _group_type character, _add boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _group_id INT;
BEGIN
  PERFORM contact_toggle_system_group(_contact.id, _contact.org_id, _group_type, _add);
END;
$$;


ALTER FUNCTION public.contact_toggle_system_group(_contact public.contacts_contact, _group_type character, _add boolean) OWNER TO flowartisan;

--
-- Name: contact_toggle_system_group(integer, integer, character, boolean); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.contact_toggle_system_group(_contact_id integer, _org_id integer, _group_type character, _add boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _group_id INT;
BEGIN
  -- lookup the group id
  SELECT id INTO STRICT _group_id FROM contacts_contactgroup
  WHERE org_id = _org_id AND group_type = _group_type;
  -- don't do anything if group doesn't exist for some inexplicable reason
  IF _group_id IS NULL THEN
    RETURN;
  END IF;
  IF _add THEN
    BEGIN
      INSERT INTO contacts_contactgroup_contacts (contactgroup_id, contact_id) VALUES (_group_id, _contact_id);
    EXCEPTION WHEN unique_violation THEN
      -- do nothing
    END;
  ELSE
    DELETE FROM contacts_contactgroup_contacts WHERE contactgroup_id = _group_id AND contact_id = _contact_id;
  END IF;
END;
$$;


ALTER FUNCTION public.contact_toggle_system_group(_contact_id integer, _org_id integer, _group_type character, _add boolean) OWNER TO flowartisan;

--
-- Name: extract_jsonb_keys(jsonb); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.extract_jsonb_keys(_jsonb jsonb) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN ARRAY(SELECT * FROM JSONB_OBJECT_KEYS(_jsonb));
END;
$$;


ALTER FUNCTION public.extract_jsonb_keys(_jsonb jsonb) OWNER TO flowartisan;

--
-- Name: msgs_broadcast; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_broadcast (
    id integer NOT NULL,
    raw_urns text[],
    base_language character varying(4) NOT NULL,
    text public.hstore NOT NULL,
    media public.hstore,
    status character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    send_all boolean NOT NULL,
    metadata text,
    channel_id integer,
    created_by_id integer,
    modified_by_id integer,
    org_id integer NOT NULL,
    parent_id integer,
    schedule_id integer,
    ticket_id integer
);


ALTER TABLE public.msgs_broadcast OWNER TO flowartisan;

--
-- Name: temba_broadcast_determine_system_label(public.msgs_broadcast); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_broadcast_determine_system_label(_broadcast public.msgs_broadcast) RETURNS character
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _broadcast.schedule_id IS NOT NULL THEN
    RETURN 'E';
  END IF;

  IF _broadcast.status = 'Q' THEN
    RETURN 'O';
  END IF;

  RETURN NULL; -- does not match any label
END;
$$;


ALTER FUNCTION public.temba_broadcast_determine_system_label(_broadcast public.msgs_broadcast) OWNER TO flowartisan;

--
-- Name: temba_broadcast_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_broadcast_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new_label_type CHAR(1);
  _old_label_type CHAR(1);
BEGIN
  -- new broadcast inserted
  IF TG_OP = 'INSERT' THEN
    _new_label_type := temba_broadcast_determine_system_label(NEW);
    IF _new_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
    END IF;

  -- existing broadcast updated
  ELSIF TG_OP = 'UPDATE' THEN
    _old_label_type := temba_broadcast_determine_system_label(OLD);
    _new_label_type := temba_broadcast_determine_system_label(NEW);

    IF _old_label_type IS DISTINCT FROM _new_label_type THEN
      IF _old_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
      END IF;
      IF _new_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
      END IF;
    END IF;

  -- existing broadcast deleted
  ELSIF TG_OP = 'DELETE' THEN
    _old_label_type := temba_broadcast_determine_system_label(OLD);

    IF _old_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_broadcast_on_change() OWNER TO flowartisan;

--
-- Name: channels_channelevent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_channelevent (
    id integer NOT NULL,
    event_type character varying(16) NOT NULL,
    extra text,
    occurred_on timestamp with time zone NOT NULL,
    created_on timestamp with time zone NOT NULL,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    contact_urn_id integer,
    org_id integer NOT NULL
);


ALTER TABLE public.channels_channelevent OWNER TO flowartisan;

--
-- Name: temba_channelevent_is_call(public.channels_channelevent); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_channelevent_is_call(_event public.channels_channelevent) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN _event.event_type IN ('mo_call', 'mo_miss', 'mt_call', 'mt_miss');
END;
$$;


ALTER FUNCTION public.temba_channelevent_is_call(_event public.channels_channelevent) OWNER TO flowartisan;

--
-- Name: temba_channelevent_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_channelevent_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- new event inserted
  IF TG_OP = 'INSERT' THEN
    -- don't update anything for a non-call event
    IF NOT temba_channelevent_is_call(NEW) THEN
      RETURN NULL;
    END IF;

    PERFORM temba_insert_system_label(NEW.org_id, 'C', 1);

  -- existing call updated
  ELSIF TG_OP = 'UPDATE' THEN
    -- don't update anything for a non-call event
    IF NOT temba_channelevent_is_call(NEW) THEN
      RETURN NULL;
    END IF;

  -- existing call deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- don't update anything for a non-call event
    IF NOT temba_channelevent_is_call(OLD) THEN
      RETURN NULL;
    END IF;

    PERFORM temba_insert_system_label(OLD.org_id, 'C', -1);

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_channelevent_on_change() OWNER TO flowartisan;

--
-- Name: temba_flowrun_delete(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_flowrun_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    p INT;
    _path_json JSONB;
    _path_len INT;
BEGIN
    -- if we're deleting a run which is sitting at a node, decrement that node's count
    IF OLD.status IN ('A', 'W') AND OLD.current_node_uuid IS NOT NULL THEN
        PERFORM temba_insert_flownodecount(OLD.flow_id, OLD.current_node_uuid, -1);
    END IF;

    -- if this is a user delete then remove from results
    IF OLD.delete_from_results THEN
        PERFORM temba_insert_flowrunstatuscount(OLD.flow_id, OLD.status, -1);
        PERFORM temba_update_category_counts(OLD.flow_id, NULL, OLD.results::json);

        -- nothing more to do if path was empty
        IF OLD.path IS NULL OR OLD.path = '[]' THEN RETURN NULL; END IF;

        -- parse path as JSON
        _path_json := OLD.path::json;
        _path_len := jsonb_array_length(_path_json);

        -- for each step in the path, decrement the path count
        p := 1;
        LOOP
            EXIT WHEN p >= _path_len;

            -- it's possible that steps from old flows don't have exit_uuid
            IF (_path_json->(p-1)->'exit_uuid') IS NOT NULL THEN
                PERFORM temba_insert_flowpathcount(
                    OLD.flow_id,
                    UUID(_path_json->(p-1)->>'exit_uuid'),
                    UUID(_path_json->p->>'node_uuid'),
                    timestamptz(_path_json->p->>'arrived_on'),
                    -1
                );
            END IF;

            p := p + 1;
        END LOOP;
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_flowrun_delete() OWNER TO flowartisan;

--
-- Name: temba_flowrun_insert(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_flowrun_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    p INT;
    _path_json JSONB;
    _path_len INT;
BEGIN
    -- increment count for runs with this flow and status
    PERFORM temba_insert_flowrunstatuscount(NEW.flow_id, NEW.status, 1);

    -- if this run is part of a flow start, increment that start's count of runs
    IF NEW.start_id IS NOT NULL THEN
        PERFORM temba_insert_flowstartcount(NEW.start_id, 1);
    END IF;

    -- increment node count at current node in this path if this is an active run
    IF NEW.status IN ('A', 'W') AND NEW.current_node_uuid IS NOT NULL THEN
        PERFORM temba_insert_flownodecount(NEW.flow_id, NEW.current_node_uuid, 1);
    END IF;

    -- nothing more to do if path is empty
    IF NEW.path IS NULL OR NEW.path = '[]' THEN RETURN NULL; END IF;

    -- parse path as JSON
    _path_json := NEW.path::json;
    _path_len := jsonb_array_length(_path_json);

    -- for each step in the path, increment the path count, and record a recent run
    p := 1;
    LOOP
        EXIT WHEN p >= _path_len;

        PERFORM temba_insert_flowpathcount(
            NEW.flow_id,
            UUID(_path_json->(p-1)->>'exit_uuid'),
            UUID(_path_json->p->>'node_uuid'),
            timestamptz(_path_json->p->>'arrived_on'),
            1
        );
        p := p + 1;
    END LOOP;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_flowrun_insert() OWNER TO flowartisan;

--
-- Name: temba_flowrun_path_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_flowrun_path_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  p INT;
  _old_path_json JSONB;
  _new_path_json JSONB;
  _old_path_len INT;
  _new_path_len INT;
  _old_last_step_uuid TEXT;
BEGIN
    _old_path_json := COALESCE(OLD.path, '[]')::jsonb;
    _new_path_json := COALESCE(NEW.path, '[]')::jsonb;
    _old_path_len := jsonb_array_length(_old_path_json);
    _new_path_len := jsonb_array_length(_new_path_json);

    -- we don't support rewinding run paths, so the new path must be longer than the old
    IF _new_path_len < _old_path_len THEN RAISE EXCEPTION 'Cannot rewind a flow run path'; END IF;

    -- update the node counts
    IF _old_path_len > 0 AND OLD.status IN ('A', 'W') THEN
        PERFORM temba_insert_flownodecount(OLD.flow_id, UUID(_old_path_json->(_old_path_len-1)->>'node_uuid'), -1);
    END IF;

    IF _new_path_len > 0 AND NEW.status IN ('A', 'W') THEN
        PERFORM temba_insert_flownodecount(NEW.flow_id, UUID(_new_path_json->(_new_path_len-1)->>'node_uuid'), 1);
    END IF;

    -- if we have an old path, find its last step in the new path, and that will be our starting point
    IF _old_path_len > 1 THEN
        _old_last_step_uuid := _old_path_json->(_old_path_len-1)->>'uuid';

        -- old and new paths end with same step so path activity doesn't change
        IF _old_last_step_uuid = _new_path_json->(_new_path_len-1)->>'uuid' THEN
            RETURN NULL;
        END IF;

        p := _new_path_len - 1;
        LOOP
            EXIT WHEN p = 1 OR _new_path_json->(p-1)->>'uuid' = _old_last_step_uuid;
            p := p - 1;
        END LOOP;
    ELSE
        p := 1;
    END IF;

    LOOP
      EXIT WHEN p >= _new_path_len;
      PERFORM temba_insert_flowpathcount(
          NEW.flow_id,
          UUID(_new_path_json->(p-1)->>'exit_uuid'),
          UUID(_new_path_json->p->>'node_uuid'),
          timestamptz(_new_path_json->p->>'arrived_on'),
          1
      );
      p := p + 1;
    END LOOP;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_flowrun_path_change() OWNER TO flowartisan;

--
-- Name: temba_flowrun_status_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_flowrun_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- restrict changes
    IF OLD.status NOT IN ('A', 'W') AND NEW.status IN ('A', 'W') THEN RAISE EXCEPTION 'Cannot restart an exited flow run'; END IF;

    IF OLD.status != NEW.status THEN
        PERFORM temba_insert_flowrunstatuscount(OLD.flow_id, OLD.status, -1);
        PERFORM temba_insert_flowrunstatuscount(NEW.flow_id, NEW.status, 1);
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_flowrun_status_change() OWNER TO flowartisan;

--
-- Name: temba_insert_broadcastmsgcount(integer, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_broadcastmsgcount(_broadcast_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    IF _broadcast_id IS NOT NULL THEN
      INSERT INTO msgs_broadcastmsgcount("broadcast_id", "count", "is_squashed")
        VALUES(_broadcast_id, _count, FALSE);
    END IF;
  END;
$$;


ALTER FUNCTION public.temba_insert_broadcastmsgcount(_broadcast_id integer, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_channelcount(integer, character varying, date, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_channelcount(_channel_id integer, _count_type character varying, _count_day date, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    IF _channel_id IS NOT NULL THEN
      INSERT INTO channels_channelcount("channel_id", "count_type", "day", "count", "is_squashed")
        VALUES(_channel_id, _count_type, _count_day, _count, FALSE);
    END IF;
  END;
$$;


ALTER FUNCTION public.temba_insert_channelcount(_channel_id integer, _count_type character varying, _count_day date, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_flowcategorycount(integer, text, json, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_flowcategorycount(_flow_id integer, result_key text, _result json, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    IF _result->>'category' IS NOT NULL THEN
      INSERT INTO flows_flowcategorycount("flow_id", "node_uuid", "result_key", "result_name", "category_name", "count", "is_squashed")
        VALUES(_flow_id, (_result->>'node_uuid')::uuid, result_key, _result->>'name', _result->>'category', _count, FALSE);
    END IF;
  END;
$$;


ALTER FUNCTION public.temba_insert_flowcategorycount(_flow_id integer, result_key text, _result json, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_flownodecount(integer, uuid, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_flownodecount(_flow_id integer, _node_uuid uuid, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
      VALUES(_flow_id, _node_uuid, _count, FALSE);
  END;
$$;


ALTER FUNCTION public.temba_insert_flownodecount(_flow_id integer, _node_uuid uuid, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_flowpathcount(integer, uuid, uuid, timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_flowpathcount(_flow_id integer, _from_uuid uuid, _to_uuid uuid, _period timestamp with time zone, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO flows_flowpathcount("flow_id", "from_uuid", "to_uuid", "period", "count", "is_squashed")
      VALUES(_flow_id, _from_uuid, _to_uuid, date_trunc('hour', _period), _count, FALSE);
  END;
$$;


ALTER FUNCTION public.temba_insert_flowpathcount(_flow_id integer, _from_uuid uuid, _to_uuid uuid, _period timestamp with time zone, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_flowrunstatuscount(integer, character, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_flowrunstatuscount(_flow_id integer, _status character, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    _exit_type CHAR(1);
BEGIN
    _exit_type := CASE _status
        WHEN 'A' THEN NULL
        WHEN 'W' THEN NULL
        WHEN 'I' THEN 'I'
        WHEN 'C' THEN 'C'
        WHEN 'X' THEN 'E'
        WHEN 'F' THEN 'F'
    END;

    INSERT INTO flows_flowruncount("flow_id", "exit_type", "count", "is_squashed")
    VALUES(_flow_id, _exit_type, _count, FALSE);
END;
$$;


ALTER FUNCTION public.temba_insert_flowrunstatuscount(_flow_id integer, _status character, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_flowstartcount(integer, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_flowstartcount(_start_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _start_id IS NOT NULL THEN
    INSERT INTO flows_flowstartcount("start_id", "count", "is_squashed")
    VALUES(_start_id, _count, FALSE);
  END IF;
END;
$$;


ALTER FUNCTION public.temba_insert_flowstartcount(_start_id integer, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_label_count(integer, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_label_count(_label_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "is_archived", "count", "is_squashed")
  VALUES(_label_id, FALSE, _count, FALSE);
END;
$$;


ALTER FUNCTION public.temba_insert_label_count(_label_id integer, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_message_label_counts(bigint, boolean, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_message_label_counts(_msg_id bigint, _is_archived boolean, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "count", "is_archived", "is_squashed")
  SELECT label_id, _count, _is_archived, FALSE FROM msgs_msg_labels WHERE msgs_msg_labels.msg_id = _msg_id;
END;
$$;


ALTER FUNCTION public.temba_insert_message_label_counts(_msg_id bigint, _is_archived boolean, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_notificationcount(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_notificationcount(_org_id integer, _user_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO notifications_notificationcount("org_id", "user_id", "count", "is_squashed")
  VALUES(_org_id, _user_id, _count, FALSE);
END;
$$;


ALTER FUNCTION public.temba_insert_notificationcount(_org_id integer, _user_id integer, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_system_label(integer, character, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_system_label(_org_id integer, _label_type character, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_systemlabelcount("org_id", "label_type", "is_archived", "count", "is_squashed")
  VALUES(_org_id, _label_type, FALSE, _count, FALSE);
END;
$$;


ALTER FUNCTION public.temba_insert_system_label(_org_id integer, _label_type character, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_ticketcount(integer, integer, character, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_ticketcount(_org_id integer, _assignee_id integer, status character, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO tickets_ticketcount("org_id", "assignee_id", "status", "count", "is_squashed")
    VALUES(_org_id, _assignee_id, status, _count, FALSE);
  END;
$$;


ALTER FUNCTION public.temba_insert_ticketcount(_org_id integer, _assignee_id integer, status character, _count integer) OWNER TO flowartisan;

--
-- Name: temba_insert_topupcredits(integer, integer); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_insert_topupcredits(_topup_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO orgs_topupcredits("topup_id", "used", "is_squashed") VALUES(_topup_id, _count, FALSE);
END;
$$;


ALTER FUNCTION public.temba_insert_topupcredits(_topup_id integer, _count integer) OWNER TO flowartisan;

--
-- Name: msgs_msg; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_msg (
    id bigint NOT NULL,
    uuid uuid,
    text text NOT NULL,
    attachments character varying(2048)[],
    high_priority boolean,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone,
    sent_on timestamp with time zone,
    queued_on timestamp with time zone,
    msg_type character varying(1),
    direction character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    visibility character varying(1) NOT NULL,
    msg_count integer NOT NULL,
    error_count integer NOT NULL,
    next_attempt timestamp with time zone,
    failed_reason character varying(1),
    external_id character varying(255),
    metadata text,
    broadcast_id integer,
    channel_id integer,
    contact_id integer NOT NULL,
    contact_urn_id integer,
    flow_id integer,
    org_id integer NOT NULL,
    topup_id integer,
    CONSTRAINT no_sent_status_without_sent_on CHECK ((NOT ((sent_on IS NULL) AND ((status)::text = ANY ((ARRAY['W'::character varying, 'S'::character varying, 'D'::character varying])::text[])))))
);


ALTER TABLE public.msgs_msg OWNER TO flowartisan;

--
-- Name: temba_msg_determine_system_label(public.msgs_msg); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_msg_determine_system_label(_msg public.msgs_msg) RETURNS character
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _msg.direction = 'I' THEN
    IF _msg.visibility = 'V' THEN
      IF _msg.msg_type = 'I' THEN
        RETURN 'I';
      ELSIF _msg.msg_type = 'F' THEN
        RETURN 'W';
      END IF;
    ELSIF _msg.visibility = 'A' THEN
      RETURN 'A';
    END IF;
  ELSE
    IF _msg.VISIBILITY = 'V' THEN
      IF _msg.status = 'P' OR _msg.status = 'Q' THEN
        RETURN 'O';
      ELSIF _msg.status = 'W' OR _msg.status = 'S' OR _msg.status = 'D' THEN
        RETURN 'S';
      ELSIF _msg.status = 'F' THEN
        RETURN 'X';
      END IF;
    END IF;
  END IF;

  RETURN NULL; -- might not match any label
END;
$$;


ALTER FUNCTION public.temba_msg_determine_system_label(_msg public.msgs_msg) OWNER TO flowartisan;

--
-- Name: temba_msg_labels_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_msg_labels_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_visible BOOLEAN;
BEGIN
  -- label applied to message
  IF TG_OP = 'INSERT' THEN
    -- is this message visible
    SELECT msgs_msg.visibility = 'V'
    INTO STRICT is_visible FROM msgs_msg
    WHERE msgs_msg.id = NEW.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(NEW.label_id, 1);
    END IF;

  -- label removed from message
  ELSIF TG_OP = 'DELETE' THEN
    -- is this message visible and why is it being deleted?
    SELECT msgs_msg.visibility = 'V' INTO STRICT is_visible
    FROM msgs_msg WHERE msgs_msg.id = OLD.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(OLD.label_id, -1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_msg_labels_on_change() OWNER TO flowartisan;

--
-- Name: temba_msg_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_msg_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new_label_type CHAR(1);
  _old_label_type CHAR(1);
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- prevent illegal message states
    IF NEW.direction = 'I' AND NEW.status NOT IN ('P', 'H') THEN
      RAISE EXCEPTION 'Incoming messages can only be PENDING or HANDLED';
    END IF;
    IF NEW.direction = 'O' AND NEW.visibility = 'A' THEN
      RAISE EXCEPTION 'Outgoing messages cannot be archived';
    END IF;
  END IF;

  -- new message inserted
  IF TG_OP = 'INSERT' THEN
    _new_label_type := temba_msg_determine_system_label(NEW);
    IF _new_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
    END IF;

    IF NEW.broadcast_id IS NOT NULL THEN
      PERFORM temba_insert_broadcastmsgcount(NEW.broadcast_id, 1);
    END IF;

  -- existing message updated
  ELSIF TG_OP = 'UPDATE' THEN
    _old_label_type := temba_msg_determine_system_label(OLD);
    _new_label_type := temba_msg_determine_system_label(NEW);

    IF _old_label_type IS DISTINCT FROM _new_label_type THEN
      IF _old_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
      END IF;
      IF _new_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
      END IF;
    END IF;

    -- is being archived or deleted (i.e. no longer included for user labels)
    IF OLD.visibility = 'V' AND NEW.visibility != 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, FALSE, -1);
    END IF;

    -- is being restored (i.e. now included for user labels)
    IF OLD.visibility != 'V' AND NEW.visibility = 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, FALSE, 1);
    END IF;

    -- update our broadcast msg count if it changed
    IF NEW.broadcast_id IS DISTINCT FROM OLD.broadcast_id THEN
      PERFORM temba_insert_broadcastmsgcount(OLD.broadcast_id, -1);
      PERFORM temba_insert_broadcastmsgcount(NEW.broadcast_id, 1);
    END IF;

  -- existing message deleted
  ELSIF TG_OP = 'DELETE' THEN
    _old_label_type := temba_msg_determine_system_label(OLD);

    IF _old_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_msg_on_change() OWNER TO flowartisan;

--
-- Name: temba_notification_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_notification_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT NEW.is_seen THEN -- new notification inserted
    PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, 1);
  ELSIF TG_OP = 'UPDATE' THEN -- existing notification updated
    IF OLD.is_seen AND NOT NEW.is_seen THEN -- becoming unseen again
      PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, 1);
    ELSIF NOT OLD.is_seen AND NEW.is_seen THEN -- becoming seen
      PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, -1);
    END IF;
  ELSIF TG_OP = 'DELETE' AND NOT OLD.is_seen THEN -- existing notification deleted
    PERFORM temba_insert_notificationcount(OLD.org_id, OLD.user_id, -1);
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_notification_on_change() OWNER TO flowartisan;

--
-- Name: temba_reset_system_labels(character[]); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_reset_system_labels(_label_types character[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM msgs_systemlabelcount WHERE label_type = ANY(_label_types);
END;
$$;


ALTER FUNCTION public.temba_reset_system_labels(_label_types character[]) OWNER TO flowartisan;

--
-- Name: temba_ticket_on_change(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_ticket_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN -- new ticket inserted
    PERFORM temba_insert_ticketcount(NEW.org_id, NEW.assignee_id, NEW.status, 1);

    IF NEW.status = 'O' THEN
      UPDATE contacts_contact SET ticket_count = ticket_count + 1, modified_on = NOW() WHERE id = NEW.contact_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN -- existing ticket updated
    IF OLD.assignee_id IS DISTINCT FROM NEW.assignee_id OR OLD.status != NEW.status THEN
      PERFORM temba_insert_ticketcount(OLD.org_id, OLD.assignee_id, OLD.status, -1);
      PERFORM temba_insert_ticketcount(NEW.org_id, NEW.assignee_id, NEW.status, 1);
    END IF;

    IF OLD.status = 'O' AND NEW.status = 'C' THEN -- ticket closed
      UPDATE contacts_contact SET ticket_count = ticket_count - 1, modified_on = NOW() WHERE id = OLD.contact_id;
    ELSIF OLD.status = 'C' AND NEW.status = 'O' THEN -- ticket reopened
      UPDATE contacts_contact SET ticket_count = ticket_count + 1, modified_on = NOW() WHERE id = OLD.contact_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN -- existing ticket deleted
    PERFORM temba_insert_ticketcount(OLD.org_id, OLD.assignee_id, OLD.status, -1);

    IF OLD.status = 'O' THEN -- open ticket deleted
      UPDATE contacts_contact SET ticket_count = ticket_count - 1, modified_on = NOW() WHERE id = OLD.contact_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_ticket_on_change() OWNER TO flowartisan;

--
-- Name: temba_update_category_counts(integer, json, json); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_category_counts(_flow_id integer, new json, old json) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  DECLARE node_uuid text;
  DECLARE result_key text;
  DECLARE result_value text;
  DECLARE value_key text;
  DECLARE value_value text;
  DECLARE _new json;
  DECLARE _old json;
BEGIN
    -- look over the keys in our new results
    FOR result_key, result_value IN SELECT key, value from json_each(new)
    LOOP
        -- if its a new key, create a new count
        IF (old->result_key) IS NULL THEN
            execute temba_insert_flowcategorycount(_flow_id, result_key, new->result_key, 1);
        ELSE
            _new := new->result_key;
            _old := old->result_key;

            IF (_old->>'node_uuid') = (_new->>'node_uuid') THEN
                -- we already have this key, check if the value is newer
                IF timestamptz(_new->>'created_on') > timestamptz(_old->>'created_on') THEN
                    -- found an update to an existing key, create a negative and positive count accordingly
                    execute temba_insert_flowcategorycount(_flow_id, result_key, _old, -1);
                    execute temba_insert_flowcategorycount(_flow_id, result_key, _new, 1);
                END IF;
            ELSE
                -- the parent has changed, out with the old in with the new
                execute temba_insert_flowcategorycount(_flow_id, result_key, _old, -1);
                execute temba_insert_flowcategorycount(_flow_id, result_key, _new, 1);
            END IF;
        END IF;
    END LOOP;

    -- look over keys in our old results that might now be gone
    FOR result_key, result_value IN SELECT key, value from json_each(old)
    LOOP
        IF (new->result_key) IS NULL THEN
            -- found a key that's since been deleted, add a negation
            execute temba_insert_flowcategorycount(_flow_id, result_key, old->result_key, -1);
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.temba_update_category_counts(_flow_id integer, new json, old json) OWNER TO flowartisan;

--
-- Name: temba_update_channelcount(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_channelcount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Message being updated
  IF TG_OP = 'INSERT' THEN
    -- Return if there is no channel on this message
    IF NEW.channel_id IS NULL THEN
      RETURN NULL;
    END IF;

    -- If this is an incoming message, without message type, then increment that count
    IF NEW.direction = 'I' THEN
      -- This is a voice message, increment that count
      IF NEW.msg_type = 'V' THEN
        PERFORM temba_insert_channelcount(NEW.channel_id, 'IV', NEW.created_on::date, 1);
      -- Otherwise, this is a normal message
      ELSE
        PERFORM temba_insert_channelcount(NEW.channel_id, 'IM', NEW.created_on::date, 1);
      END IF;

    -- This is an outgoing message
    ELSIF NEW.direction = 'O' THEN
      -- This is a voice message, increment that count
      IF NEW.msg_type = 'V' THEN
        PERFORM temba_insert_channelcount(NEW.channel_id, 'OV', NEW.created_on::date, 1);
      -- Otherwise, this is a normal message
      ELSE
        PERFORM temba_insert_channelcount(NEW.channel_id, 'OM', NEW.created_on::date, 1);
      END IF;

    END IF;

  -- Assert that updates aren't happening that we don't approve of
  ELSIF TG_OP = 'UPDATE' THEN
    -- If the direction is changing, blow up
    IF NEW.direction <> OLD.direction THEN
      RAISE EXCEPTION 'Cannot change direction on messages';
    END IF;

    -- Cannot move from IVR to Text, or IVR to Text
    IF (OLD.msg_type <> 'V' AND NEW.msg_type = 'V') OR (OLD.msg_type = 'V' AND NEW.msg_type <> 'V') THEN
      RAISE EXCEPTION 'Cannot change a message from voice to something else or vice versa';
    END IF;

    -- Cannot change created_on
    IF NEW.created_on <> OLD.created_on THEN
      RAISE EXCEPTION 'Cannot change created_on on messages';
    END IF;

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_update_channelcount() OWNER TO flowartisan;

--
-- Name: temba_update_channellog_count(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_channellog_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- ChannelLog being added
  IF TG_OP = 'INSERT' THEN
    -- Error, increment our error count
    IF NEW.is_error THEN
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LE', NULL::date, 1);
    -- Success, increment that count instead
    ELSE
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LS', NULL::date, 1);
    END IF;

  -- Updating is_error is forbidden
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Cannot update is_error or channel_id on ChannelLog events';

  -- Deleting, decrement our count
  ELSIF TG_OP = 'DELETE' THEN
    -- Error, decrement our error count
    IF OLD.is_error THEN
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LE', NULL::date, -1);
    -- Success, decrement that count instead
    ELSE
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LS', NULL::date, -1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_update_channellog_count() OWNER TO flowartisan;

--
-- Name: temba_update_flowcategorycount(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_flowcategorycount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        EXECUTE temba_update_category_counts(NEW.flow_id, NEW.results::json, NULL);
    ELSIF TG_OP = 'UPDATE' THEN
        -- use string comparison to check for no-change case
        IF NEW.results = OLD.results THEN RETURN NULL; END IF;

        EXECUTE temba_update_category_counts(NEW.flow_id, NEW.results::json, OLD.results::json);
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_update_flowcategorycount() OWNER TO flowartisan;

--
-- Name: temba_update_topupcredits(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_topupcredits() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Msg is being created
  IF TG_OP = 'INSERT' THEN
    -- If we have a topup, increment our # of used credits
    IF NEW.topup_id IS NOT NULL THEN
      PERFORM temba_insert_topupcredits(NEW.topup_id, 1);
    END IF;

  -- Msg is being updated
  ELSIF TG_OP = 'UPDATE' THEN
    -- If the topup has changed
    IF NEW.topup_id IS DISTINCT FROM OLD.topup_id THEN
      -- If our old topup wasn't null then decrement our used credits on it
      IF OLD.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(OLD.topup_id, -1);
      END IF;

      -- if our new topup isn't null, then increment our used credits on it
      IF NEW.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(NEW.topup_id, 1);
      END IF;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_update_topupcredits() OWNER TO flowartisan;

--
-- Name: temba_update_topupcredits_for_debit(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.temba_update_topupcredits_for_debit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Debit is being created
  IF TG_OP = 'INSERT' THEN
    -- If we are an allocation and have a topup, increment our # of used credits
    IF NEW.topup_id IS NOT NULL AND NEW.debit_type = 'A' THEN
      PERFORM temba_insert_topupcredits(NEW.topup_id, NEW.amount);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.temba_update_topupcredits_for_debit() OWNER TO flowartisan;

--
-- Name: update_contact_system_groups(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.update_contact_system_groups() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- new contact added
  IF TG_OP = 'INSERT' AND NEW.is_active THEN
    IF NEW.status = 'A' THEN
      PERFORM contact_toggle_system_group(NEW, 'A', true);
    ELSIF NEW.status = 'B' THEN
      PERFORM contact_toggle_system_group(NEW, 'B', true);
    ELSIF NEW.status = 'S' THEN
      PERFORM contact_toggle_system_group(NEW, 'S', true);
    ELSIF NEW.status = 'V' THEN
      PERFORM contact_toggle_system_group(NEW, 'V', true);
    END IF;
  END IF;

  -- existing contact updated
  IF TG_OP = 'UPDATE' THEN
    -- do nothing for inactive contacts
    IF NOT OLD.is_active AND NOT NEW.is_active THEN
      RETURN NULL;
    END IF;

    IF OLD.status != NEW.status THEN
      PERFORM contact_toggle_system_group(NEW, OLD.status, false);
      PERFORM contact_toggle_system_group(NEW, NEW.status, true);
    END IF;

    -- is being released
    IF OLD.is_active AND NOT NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, 'A', false);
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      PERFORM contact_toggle_system_group(NEW, 'S', false);
      PERFORM contact_toggle_system_group(NEW, 'V', false);
    END IF;

    -- is being unreleased
    IF NOT OLD.is_active AND NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, NEW.status, true);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_contact_system_groups() OWNER TO flowartisan;

--
-- Name: update_group_count(); Type: FUNCTION; Schema: public; Owner: flowartisan
--

CREATE FUNCTION public.update_group_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- contact being added to group
  IF TG_OP = 'INSERT' THEN
    INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed") VALUES(NEW.contactgroup_id, 1, FALSE);

  -- contact being removed from a group
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed") VALUES(OLD.contactgroup_id, -1, FALSE);

  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_group_count() OWNER TO flowartisan;

--
-- Name: airtime_airtimetransfer; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.airtime_airtimetransfer (
    id integer NOT NULL,
    status character varying(1) NOT NULL,
    recipient character varying(255) NOT NULL,
    sender character varying(255),
    currency character varying(32),
    desired_amount numeric(10,2) NOT NULL,
    actual_amount numeric(10,2) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    contact_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.airtime_airtimetransfer OWNER TO flowartisan;

--
-- Name: airtime_airtimetransfer_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.airtime_airtimetransfer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.airtime_airtimetransfer_id_seq OWNER TO flowartisan;

--
-- Name: airtime_airtimetransfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.airtime_airtimetransfer_id_seq OWNED BY public.airtime_airtimetransfer.id;


--
-- Name: api_apitoken; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.api_apitoken (
    is_active boolean NOT NULL,
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    role_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.api_apitoken OWNER TO flowartisan;

--
-- Name: api_resthook; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.api_resthook (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    slug character varying(50) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.api_resthook OWNER TO flowartisan;

--
-- Name: api_resthook_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.api_resthook_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.api_resthook_id_seq OWNER TO flowartisan;

--
-- Name: api_resthook_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.api_resthook_id_seq OWNED BY public.api_resthook.id;


--
-- Name: api_resthooksubscriber; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.api_resthooksubscriber (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    target_url character varying(200) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    resthook_id integer NOT NULL
);


ALTER TABLE public.api_resthooksubscriber OWNER TO flowartisan;

--
-- Name: api_resthooksubscriber_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.api_resthooksubscriber_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.api_resthooksubscriber_id_seq OWNER TO flowartisan;

--
-- Name: api_resthooksubscriber_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.api_resthooksubscriber_id_seq OWNED BY public.api_resthooksubscriber.id;


--
-- Name: api_webhookevent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.api_webhookevent (
    id integer NOT NULL,
    data text NOT NULL,
    action character varying(8) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    resthook_id integer NOT NULL
);


ALTER TABLE public.api_webhookevent OWNER TO flowartisan;

--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.api_webhookevent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.api_webhookevent_id_seq OWNER TO flowartisan;

--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.api_webhookevent_id_seq OWNED BY public.api_webhookevent.id;


--
-- Name: apks_apk; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.apks_apk (
    id integer NOT NULL,
    apk_type character varying(1) NOT NULL,
    apk_file character varying(100) NOT NULL,
    version text NOT NULL,
    pack integer,
    description text,
    created_on timestamp with time zone NOT NULL
);


ALTER TABLE public.apks_apk OWNER TO flowartisan;

--
-- Name: apks_apk_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.apks_apk_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.apks_apk_id_seq OWNER TO flowartisan;

--
-- Name: apks_apk_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.apks_apk_id_seq OWNED BY public.apks_apk.id;


--
-- Name: archives_archive; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.archives_archive (
    id integer NOT NULL,
    archive_type character varying(16) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    period character varying(1) NOT NULL,
    start_date date NOT NULL,
    record_count integer NOT NULL,
    size bigint NOT NULL,
    hash text NOT NULL,
    url character varying(200) NOT NULL,
    needs_deletion boolean NOT NULL,
    build_time integer NOT NULL,
    deleted_on timestamp with time zone,
    org_id integer NOT NULL,
    rollup_id integer
);


ALTER TABLE public.archives_archive OWNER TO flowartisan;

--
-- Name: archives_archive_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.archives_archive_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.archives_archive_id_seq OWNER TO flowartisan;

--
-- Name: archives_archive_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.archives_archive_id_seq OWNED BY public.archives_archive.id;


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO flowartisan;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_id_seq OWNER TO flowartisan;

--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_group_id_seq OWNED BY public.auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO flowartisan;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_group_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_permissions_id_seq OWNER TO flowartisan;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_group_permissions_id_seq OWNED BY public.auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO flowartisan;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_permission_id_seq OWNER TO flowartisan;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_permission_id_seq OWNED BY public.auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(254) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


ALTER TABLE public.auth_user OWNER TO flowartisan;

--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.auth_user_groups OWNER TO flowartisan;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_user_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_groups_id_seq OWNER TO flowartisan;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_user_groups_id_seq OWNED BY public.auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_id_seq OWNER TO flowartisan;

--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_user_user_permissions OWNER TO flowartisan;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.auth_user_user_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_user_permissions_id_seq OWNER TO flowartisan;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.auth_user_user_permissions_id_seq OWNED BY public.auth_user_user_permissions.id;


--
-- Name: authtoken_token; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.authtoken_token (
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.authtoken_token OWNER TO flowartisan;

--
-- Name: campaigns_campaign; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.campaigns_campaign (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    name character varying(64) NOT NULL,
    is_archived boolean NOT NULL,
    created_by_id integer NOT NULL,
    group_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.campaigns_campaign OWNER TO flowartisan;

--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.campaigns_campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.campaigns_campaign_id_seq OWNER TO flowartisan;

--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.campaigns_campaign_id_seq OWNED BY public.campaigns_campaign.id;


--
-- Name: campaigns_campaignevent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.campaigns_campaignevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    event_type character varying(1) NOT NULL,
    "offset" integer NOT NULL,
    unit character varying(1) NOT NULL,
    start_mode character varying(1) NOT NULL,
    message public.hstore,
    delivery_hour integer NOT NULL,
    campaign_id integer NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    relative_to_id integer NOT NULL
);


ALTER TABLE public.campaigns_campaignevent OWNER TO flowartisan;

--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.campaigns_campaignevent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.campaigns_campaignevent_id_seq OWNER TO flowartisan;

--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.campaigns_campaignevent_id_seq OWNED BY public.campaigns_campaignevent.id;


--
-- Name: campaigns_eventfire; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.campaigns_eventfire (
    id integer NOT NULL,
    scheduled timestamp with time zone NOT NULL,
    fired timestamp with time zone,
    fired_result character varying(1),
    contact_id integer NOT NULL,
    event_id integer NOT NULL
);


ALTER TABLE public.campaigns_eventfire OWNER TO flowartisan;

--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.campaigns_eventfire_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.campaigns_eventfire_id_seq OWNER TO flowartisan;

--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.campaigns_eventfire_id_seq OWNED BY public.campaigns_eventfire.id;


--
-- Name: channels_alert; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_alert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    alert_type character varying(1) NOT NULL,
    ended_on timestamp with time zone,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    sync_event_id integer
);


ALTER TABLE public.channels_alert OWNER TO flowartisan;

--
-- Name: channels_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_alert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_alert_id_seq OWNER TO flowartisan;

--
-- Name: channels_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_alert_id_seq OWNED BY public.channels_alert.id;


--
-- Name: channels_channel; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_channel (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    channel_type character varying(3) NOT NULL,
    name character varying(64),
    address character varying(255),
    country character varying(2),
    claim_code character varying(16),
    secret character varying(64),
    last_seen timestamp with time zone NOT NULL,
    device character varying(255),
    os character varying(255),
    alert_email character varying(254),
    config text,
    schemes character varying(16)[] NOT NULL,
    role character varying(4) NOT NULL,
    bod text,
    tps integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer,
    parent_id integer,
    is_system boolean NOT NULL
);


ALTER TABLE public.channels_channel OWNER TO flowartisan;

--
-- Name: channels_channel_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_channel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_channel_id_seq OWNER TO flowartisan;

--
-- Name: channels_channel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_channel_id_seq OWNED BY public.channels_channel.id;


--
-- Name: channels_channelconnection; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_channelconnection (
    id integer NOT NULL,
    connection_type character varying(1) NOT NULL,
    direction character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    external_id character varying(255) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    started_on timestamp with time zone,
    ended_on timestamp with time zone,
    duration integer,
    error_reason character varying(1),
    error_count integer NOT NULL,
    next_attempt timestamp with time zone,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    contact_urn_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.channels_channelconnection OWNER TO flowartisan;

--
-- Name: channels_channelconnection_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_channelconnection_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_channelconnection_id_seq OWNER TO flowartisan;

--
-- Name: channels_channelconnection_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_channelconnection_id_seq OWNED BY public.channels_channelconnection.id;


--
-- Name: channels_channelcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_channelcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count_type character varying(2) NOT NULL,
    day date,
    count integer NOT NULL,
    channel_id integer NOT NULL
);


ALTER TABLE public.channels_channelcount OWNER TO flowartisan;

--
-- Name: channels_channelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_channelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_channelcount_id_seq OWNER TO flowartisan;

--
-- Name: channels_channelcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_channelcount_id_seq OWNED BY public.channels_channelcount.id;


--
-- Name: channels_channelevent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_channelevent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_channelevent_id_seq OWNER TO flowartisan;

--
-- Name: channels_channelevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_channelevent_id_seq OWNED BY public.channels_channelevent.id;


--
-- Name: channels_channellog; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_channellog (
    id bigint NOT NULL,
    description character varying(255) NOT NULL,
    is_error boolean NOT NULL,
    url text,
    method character varying(16),
    request text,
    response text,
    response_status integer,
    created_on timestamp with time zone NOT NULL,
    request_time integer,
    channel_id integer NOT NULL,
    connection_id integer,
    msg_id bigint
);


ALTER TABLE public.channels_channellog OWNER TO flowartisan;

--
-- Name: channels_channellog_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_channellog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_channellog_id_seq OWNER TO flowartisan;

--
-- Name: channels_channellog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_channellog_id_seq OWNED BY public.channels_channellog.id;


--
-- Name: channels_syncevent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.channels_syncevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    power_source character varying(64) NOT NULL,
    power_status character varying(64) NOT NULL,
    power_level integer NOT NULL,
    network_type character varying(128) NOT NULL,
    lifetime integer,
    pending_message_count integer NOT NULL,
    retry_message_count integer NOT NULL,
    incoming_command_count integer NOT NULL,
    outgoing_command_count integer NOT NULL,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


ALTER TABLE public.channels_syncevent OWNER TO flowartisan;

--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.channels_syncevent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_syncevent_id_seq OWNER TO flowartisan;

--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.channels_syncevent_id_seq OWNED BY public.channels_syncevent.id;


--
-- Name: classifiers_classifier; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.classifiers_classifier (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    classifier_type character varying(16) NOT NULL,
    name character varying(64) NOT NULL,
    config jsonb NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.classifiers_classifier OWNER TO flowartisan;

--
-- Name: classifiers_classifier_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.classifiers_classifier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.classifiers_classifier_id_seq OWNER TO flowartisan;

--
-- Name: classifiers_classifier_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.classifiers_classifier_id_seq OWNED BY public.classifiers_classifier.id;


--
-- Name: classifiers_intent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.classifiers_intent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    name character varying(255) NOT NULL,
    external_id character varying(255) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    classifier_id integer NOT NULL
);


ALTER TABLE public.classifiers_intent OWNER TO flowartisan;

--
-- Name: classifiers_intent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.classifiers_intent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.classifiers_intent_id_seq OWNER TO flowartisan;

--
-- Name: classifiers_intent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.classifiers_intent_id_seq OWNED BY public.classifiers_intent.id;


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contact_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contact_id_seq OWNED BY public.contacts_contact.id;


--
-- Name: contacts_contactfield; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactfield (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    key character varying(36) NOT NULL,
    value_type character varying(1) NOT NULL,
    show_in_table boolean NOT NULL,
    priority integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL,
    name character varying(36) NOT NULL,
    CONSTRAINT contacts_contactfield_priority_check CHECK ((priority >= 0))
);


ALTER TABLE public.contacts_contactfield OWNER TO flowartisan;

--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactfield_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactfield_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactfield_id_seq OWNED BY public.contacts_contactfield.id;


--
-- Name: contacts_contactgroup; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactgroup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    group_type character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    query text,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.contacts_contactgroup OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_contacts; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactgroup_contacts (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contact_id integer NOT NULL
);


ALTER TABLE public.contacts_contactgroup_contacts OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactgroup_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactgroup_contacts_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactgroup_contacts_id_seq OWNED BY public.contacts_contactgroup_contacts.id;


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactgroup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactgroup_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactgroup_id_seq OWNED BY public.contacts_contactgroup.id;


--
-- Name: contacts_contactgroup_query_fields; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactgroup_query_fields (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contactfield_id integer NOT NULL
);


ALTER TABLE public.contacts_contactgroup_query_fields OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactgroup_query_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactgroup_query_fields_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactgroup_query_fields_id_seq OWNED BY public.contacts_contactgroup_query_fields.id;


--
-- Name: contacts_contactgroupcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactgroupcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count integer NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.contacts_contactgroupcount OWNER TO flowartisan;

--
-- Name: contacts_contactgroupcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactgroupcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactgroupcount_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactgroupcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactgroupcount_id_seq OWNED BY public.contacts_contactgroupcount.id;


--
-- Name: contacts_contactimport; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactimport (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    file character varying(100) NOT NULL,
    original_filename text NOT NULL,
    mappings jsonb NOT NULL,
    num_records integer NOT NULL,
    group_name character varying(64),
    started_on timestamp with time zone,
    status character varying(1) NOT NULL,
    finished_on timestamp with time zone,
    created_by_id integer NOT NULL,
    group_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.contacts_contactimport OWNER TO flowartisan;

--
-- Name: contacts_contactimport_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactimport_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactimport_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactimport_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactimport_id_seq OWNED BY public.contacts_contactimport.id;


--
-- Name: contacts_contactimportbatch; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contactimportbatch (
    id integer NOT NULL,
    status character varying(1) NOT NULL,
    specs jsonb NOT NULL,
    record_start integer NOT NULL,
    record_end integer NOT NULL,
    num_created integer NOT NULL,
    num_updated integer NOT NULL,
    num_errored integer NOT NULL,
    errors jsonb NOT NULL,
    finished_on timestamp with time zone,
    contact_import_id integer NOT NULL
);


ALTER TABLE public.contacts_contactimportbatch OWNER TO flowartisan;

--
-- Name: contacts_contactimportbatch_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contactimportbatch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contactimportbatch_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contactimportbatch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contactimportbatch_id_seq OWNED BY public.contacts_contactimportbatch.id;


--
-- Name: contacts_contacturn; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_contacturn (
    id integer NOT NULL,
    identity character varying(255) NOT NULL,
    scheme character varying(128) NOT NULL,
    path character varying(255) NOT NULL,
    display character varying(255),
    priority integer NOT NULL,
    auth text,
    channel_id integer,
    contact_id integer,
    org_id integer NOT NULL,
    CONSTRAINT identity_matches_scheme_and_path CHECK (((identity)::text = concat(scheme, concat(':', path)))),
    CONSTRAINT non_empty_scheme_and_path CHECK ((NOT (((scheme)::text = ''::text) OR ((path)::text = ''::text))))
);


ALTER TABLE public.contacts_contacturn OWNER TO flowartisan;

--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_contacturn_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_contacturn_id_seq OWNER TO flowartisan;

--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_contacturn_id_seq OWNED BY public.contacts_contacturn.id;


--
-- Name: contacts_exportcontactstask; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_exportcontactstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    status character varying(1) NOT NULL,
    search text,
    created_by_id integer NOT NULL,
    group_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.contacts_exportcontactstask OWNER TO flowartisan;

--
-- Name: contacts_exportcontactstask_group_memberships; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.contacts_exportcontactstask_group_memberships (
    id integer NOT NULL,
    exportcontactstask_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.contacts_exportcontactstask_group_memberships OWNER TO flowartisan;

--
-- Name: contacts_exportcontactstask_group_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_exportcontactstask_group_memberships_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_exportcontactstask_group_memberships_id_seq OWNER TO flowartisan;

--
-- Name: contacts_exportcontactstask_group_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_exportcontactstask_group_memberships_id_seq OWNED BY public.contacts_exportcontactstask_group_memberships.id;


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.contacts_exportcontactstask_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_exportcontactstask_id_seq OWNER TO flowartisan;

--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.contacts_exportcontactstask_id_seq OWNED BY public.contacts_exportcontactstask.id;


--
-- Name: csv_imports_importtask; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.csv_imports_importtask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    csv_file character varying(100) NOT NULL,
    model_class character varying(255) NOT NULL,
    import_params text,
    import_log text NOT NULL,
    import_results text,
    task_id character varying(64),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    task_status character varying(32) NOT NULL
);


ALTER TABLE public.csv_imports_importtask OWNER TO flowartisan;

--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.csv_imports_importtask_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.csv_imports_importtask_id_seq OWNER TO flowartisan;

--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.csv_imports_importtask_id_seq OWNED BY public.csv_imports_importtask.id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO flowartisan;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.django_content_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_content_type_id_seq OWNER TO flowartisan;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.django_content_type_id_seq OWNED BY public.django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO flowartisan;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.django_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_migrations_id_seq OWNER TO flowartisan;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.django_migrations_id_seq OWNED BY public.django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO flowartisan;

--
-- Name: django_site; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.django_site (
    id integer NOT NULL,
    domain character varying(100) NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.django_site OWNER TO flowartisan;

--
-- Name: django_site_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.django_site_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_site_id_seq OWNER TO flowartisan;

--
-- Name: django_site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.django_site_id_seq OWNED BY public.django_site.id;


--
-- Name: flows_exportflowresultstask; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_exportflowresultstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    status character varying(1) NOT NULL,
    config text,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.flows_exportflowresultstask OWNER TO flowartisan;

--
-- Name: flows_exportflowresultstask_flows; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_exportflowresultstask_flows (
    id integer NOT NULL,
    exportflowresultstask_id integer NOT NULL,
    flow_id integer NOT NULL
);


ALTER TABLE public.flows_exportflowresultstask_flows OWNER TO flowartisan;

--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_exportflowresultstask_flows_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_exportflowresultstask_flows_id_seq OWNER TO flowartisan;

--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_exportflowresultstask_flows_id_seq OWNED BY public.flows_exportflowresultstask_flows.id;


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_exportflowresultstask_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_exportflowresultstask_id_seq OWNER TO flowartisan;

--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_exportflowresultstask_id_seq OWNED BY public.flows_exportflowresultstask.id;


--
-- Name: flows_flow; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    is_archived boolean NOT NULL,
    is_system boolean NOT NULL,
    flow_type character varying(1) NOT NULL,
    metadata text,
    expires_after_minutes integer NOT NULL,
    ignore_triggers boolean NOT NULL,
    saved_on timestamp with time zone NOT NULL,
    base_language character varying(4),
    version_number character varying(8) NOT NULL,
    has_issues boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    saved_by_id integer NOT NULL
);


ALTER TABLE public.flows_flow OWNER TO flowartisan;

--
-- Name: flows_flow_channel_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_channel_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    channel_id integer NOT NULL
);


ALTER TABLE public.flows_flow_channel_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_channel_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_channel_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_channel_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_channel_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_channel_dependencies_id_seq OWNED BY public.flows_flow_channel_dependencies.id;


--
-- Name: flows_flow_classifier_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_classifier_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    classifier_id integer NOT NULL
);


ALTER TABLE public.flows_flow_classifier_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_classifier_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_classifier_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_classifier_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_classifier_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_classifier_dependencies_id_seq OWNED BY public.flows_flow_classifier_dependencies.id;


--
-- Name: flows_flow_field_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_field_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    contactfield_id integer NOT NULL
);


ALTER TABLE public.flows_flow_field_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_field_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_field_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_field_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_field_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_field_dependencies_id_seq OWNED BY public.flows_flow_field_dependencies.id;


--
-- Name: flows_flow_flow_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_flow_dependencies (
    id integer NOT NULL,
    from_flow_id integer NOT NULL,
    to_flow_id integer NOT NULL
);


ALTER TABLE public.flows_flow_flow_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_flow_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_flow_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_flow_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_flow_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_flow_dependencies_id_seq OWNED BY public.flows_flow_flow_dependencies.id;


--
-- Name: flows_flow_global_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_global_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    global_id integer NOT NULL
);


ALTER TABLE public.flows_flow_global_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_global_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_global_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_global_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_global_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_global_dependencies_id_seq OWNED BY public.flows_flow_global_dependencies.id;


--
-- Name: flows_flow_group_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_group_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.flows_flow_group_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_group_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_group_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_group_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_group_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_group_dependencies_id_seq OWNED BY public.flows_flow_group_dependencies.id;


--
-- Name: flows_flow_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_id_seq OWNED BY public.flows_flow.id;


--
-- Name: flows_flow_label_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_label_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    label_id integer NOT NULL
);


ALTER TABLE public.flows_flow_label_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_label_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_label_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_label_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_label_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_label_dependencies_id_seq OWNED BY public.flows_flow_label_dependencies.id;


--
-- Name: flows_flow_labels; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_labels (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    flowlabel_id integer NOT NULL
);


ALTER TABLE public.flows_flow_labels OWNER TO flowartisan;

--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_labels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_labels_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_labels_id_seq OWNED BY public.flows_flow_labels.id;


--
-- Name: flows_flow_template_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_template_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    template_id integer NOT NULL
);


ALTER TABLE public.flows_flow_template_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_template_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_template_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_template_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_template_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_template_dependencies_id_seq OWNED BY public.flows_flow_template_dependencies.id;


--
-- Name: flows_flow_ticketer_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_ticketer_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    ticketer_id integer NOT NULL
);


ALTER TABLE public.flows_flow_ticketer_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_ticketer_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_ticketer_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_ticketer_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_ticketer_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_ticketer_dependencies_id_seq OWNED BY public.flows_flow_ticketer_dependencies.id;


--
-- Name: flows_flow_topic_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_topic_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    topic_id integer NOT NULL
);


ALTER TABLE public.flows_flow_topic_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_topic_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_topic_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_topic_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_topic_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_topic_dependencies_id_seq OWNED BY public.flows_flow_topic_dependencies.id;


--
-- Name: flows_flow_user_dependencies; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flow_user_dependencies (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.flows_flow_user_dependencies OWNER TO flowartisan;

--
-- Name: flows_flow_user_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flow_user_dependencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flow_user_dependencies_id_seq OWNER TO flowartisan;

--
-- Name: flows_flow_user_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flow_user_dependencies_id_seq OWNED BY public.flows_flow_user_dependencies.id;


--
-- Name: flows_flowcategorycount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowcategorycount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    node_uuid uuid NOT NULL,
    result_key character varying(128) NOT NULL,
    result_name character varying(128) NOT NULL,
    category_name character varying(128) NOT NULL,
    count integer NOT NULL,
    flow_id integer NOT NULL
);


ALTER TABLE public.flows_flowcategorycount OWNER TO flowartisan;

--
-- Name: flows_flowcategorycount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowcategorycount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowcategorycount_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowcategorycount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowcategorycount_id_seq OWNED BY public.flows_flowcategorycount.id;


--
-- Name: flows_flowlabel; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowlabel (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    parent_id integer,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    is_active boolean NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.flows_flowlabel OWNER TO flowartisan;

--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowlabel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowlabel_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowlabel_id_seq OWNED BY public.flows_flowlabel.id;


--
-- Name: flows_flownodecount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flownodecount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    node_uuid uuid NOT NULL,
    count integer NOT NULL,
    flow_id integer NOT NULL
);


ALTER TABLE public.flows_flownodecount OWNER TO flowartisan;

--
-- Name: flows_flownodecount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flownodecount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flownodecount_id_seq OWNER TO flowartisan;

--
-- Name: flows_flownodecount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flownodecount_id_seq OWNED BY public.flows_flownodecount.id;


--
-- Name: flows_flowpathcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowpathcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    from_uuid uuid NOT NULL,
    to_uuid uuid NOT NULL,
    period timestamp with time zone NOT NULL,
    count integer NOT NULL,
    flow_id integer NOT NULL
);


ALTER TABLE public.flows_flowpathcount OWNER TO flowartisan;

--
-- Name: flows_flowpathcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowpathcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowpathcount_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowpathcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowpathcount_id_seq OWNED BY public.flows_flowpathcount.id;


--
-- Name: flows_flowrevision; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowrevision (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    definition text NOT NULL,
    spec_version character varying(8) NOT NULL,
    revision integer,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


ALTER TABLE public.flows_flowrevision OWNER TO flowartisan;

--
-- Name: flows_flowrevision_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowrevision_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowrevision_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowrevision_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowrevision_id_seq OWNED BY public.flows_flowrevision.id;


--
-- Name: flows_flowrun; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowrun (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    status character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    exited_on timestamp with time zone,
    responded boolean NOT NULL,
    results text,
    path text,
    current_node_uuid uuid,
    delete_from_results boolean,
    contact_id integer NOT NULL,
    flow_id integer NOT NULL,
    org_id integer NOT NULL,
    session_id bigint,
    start_id integer,
    submitted_by_id integer
);


ALTER TABLE public.flows_flowrun OWNER TO flowartisan;

--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowrun_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowrun_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowrun_id_seq OWNED BY public.flows_flowrun.id;


--
-- Name: flows_flowruncount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowruncount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    exit_type character varying(1),
    count integer NOT NULL,
    flow_id integer NOT NULL
);


ALTER TABLE public.flows_flowruncount OWNER TO flowartisan;

--
-- Name: flows_flowruncount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowruncount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowruncount_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowruncount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowruncount_id_seq OWNED BY public.flows_flowruncount.id;


--
-- Name: flows_flowsession; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowsession (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    status character varying(1) NOT NULL,
    session_type character varying(1) NOT NULL,
    responded boolean NOT NULL,
    output text,
    output_url character varying(2048),
    created_on timestamp with time zone NOT NULL,
    ended_on timestamp with time zone,
    wait_started_on timestamp with time zone,
    timeout_on timestamp with time zone,
    wait_expires_on timestamp with time zone,
    wait_resume_on_expire boolean NOT NULL,
    connection_id integer,
    contact_id integer NOT NULL,
    current_flow_id integer,
    org_id integer NOT NULL,
    CONSTRAINT flows_session_waiting_has_started_and_expires CHECK (((NOT ((status)::text = 'W'::text)) OR ((wait_expires_on IS NOT NULL) AND (wait_started_on IS NOT NULL))))
);


ALTER TABLE public.flows_flowsession OWNER TO flowartisan;

--
-- Name: flows_flowsession_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowsession_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowsession_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowsession_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowsession_id_seq OWNED BY public.flows_flowsession.id;


--
-- Name: flows_flowstart; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowstart (
    id integer NOT NULL,
    uuid uuid NOT NULL,
    start_type character varying(1) NOT NULL,
    urns text[],
    query text,
    restart_participants boolean NOT NULL,
    include_active boolean NOT NULL,
    status character varying(1) NOT NULL,
    extra text,
    parent_summary jsonb,
    session_history jsonb,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    contact_count integer,
    campaign_event_id integer,
    created_by_id integer,
    flow_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.flows_flowstart OWNER TO flowartisan;

--
-- Name: flows_flowstart_connections; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowstart_connections (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    channelconnection_id integer NOT NULL
);


ALTER TABLE public.flows_flowstart_connections OWNER TO flowartisan;

--
-- Name: flows_flowstart_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowstart_connections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowstart_connections_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowstart_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowstart_connections_id_seq OWNED BY public.flows_flowstart_connections.id;


--
-- Name: flows_flowstart_contacts; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowstart_contacts (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contact_id integer NOT NULL
);


ALTER TABLE public.flows_flowstart_contacts OWNER TO flowartisan;

--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowstart_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowstart_contacts_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowstart_contacts_id_seq OWNED BY public.flows_flowstart_contacts.id;


--
-- Name: flows_flowstart_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowstart_groups (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.flows_flowstart_groups OWNER TO flowartisan;

--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowstart_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowstart_groups_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowstart_groups_id_seq OWNED BY public.flows_flowstart_groups.id;


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowstart_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowstart_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowstart_id_seq OWNED BY public.flows_flowstart.id;


--
-- Name: flows_flowstartcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.flows_flowstartcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count integer NOT NULL,
    start_id integer NOT NULL
);


ALTER TABLE public.flows_flowstartcount OWNER TO flowartisan;

--
-- Name: flows_flowstartcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.flows_flowstartcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flows_flowstartcount_id_seq OWNER TO flowartisan;

--
-- Name: flows_flowstartcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.flows_flowstartcount_id_seq OWNED BY public.flows_flowstartcount.id;


--
-- Name: globals_global; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.globals_global (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    key character varying(36) NOT NULL,
    name character varying(36) NOT NULL,
    value text NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.globals_global OWNER TO flowartisan;

--
-- Name: globals_global_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.globals_global_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.globals_global_id_seq OWNER TO flowartisan;

--
-- Name: globals_global_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.globals_global_id_seq OWNED BY public.globals_global.id;


--
-- Name: locations_adminboundary; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.locations_adminboundary (
    id integer NOT NULL,
    osm_id character varying(15) NOT NULL,
    name character varying(128) NOT NULL,
    level integer NOT NULL,
    path character varying(768) NOT NULL,
    simplified_geometry public.geometry(MultiPolygon,4326),
    lft integer NOT NULL,
    rght integer NOT NULL,
    tree_id integer NOT NULL,
    parent_id integer,
    CONSTRAINT locations_adminboundary_lft_check CHECK ((lft >= 0)),
    CONSTRAINT locations_adminboundary_rght_check CHECK ((rght >= 0)),
    CONSTRAINT locations_adminboundary_tree_id_check CHECK ((tree_id >= 0))
);


ALTER TABLE public.locations_adminboundary OWNER TO flowartisan;

--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.locations_adminboundary_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.locations_adminboundary_id_seq OWNER TO flowartisan;

--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.locations_adminboundary_id_seq OWNED BY public.locations_adminboundary.id;


--
-- Name: locations_boundaryalias; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.locations_boundaryalias (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    boundary_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.locations_boundaryalias OWNER TO flowartisan;

--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.locations_boundaryalias_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.locations_boundaryalias_id_seq OWNER TO flowartisan;

--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.locations_boundaryalias_id_seq OWNED BY public.locations_boundaryalias.id;


--
-- Name: msgs_broadcast_contacts; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_broadcast_contacts (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contact_id integer NOT NULL
);


ALTER TABLE public.msgs_broadcast_contacts OWNER TO flowartisan;

--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_broadcast_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_broadcast_contacts_id_seq OWNER TO flowartisan;

--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_broadcast_contacts_id_seq OWNED BY public.msgs_broadcast_contacts.id;


--
-- Name: msgs_broadcast_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_broadcast_groups (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.msgs_broadcast_groups OWNER TO flowartisan;

--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_broadcast_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_broadcast_groups_id_seq OWNER TO flowartisan;

--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_broadcast_groups_id_seq OWNED BY public.msgs_broadcast_groups.id;


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_broadcast_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_broadcast_id_seq OWNER TO flowartisan;

--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_broadcast_id_seq OWNED BY public.msgs_broadcast.id;


--
-- Name: msgs_broadcast_urns; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_broadcast_urns (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contacturn_id integer NOT NULL
);


ALTER TABLE public.msgs_broadcast_urns OWNER TO flowartisan;

--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_broadcast_urns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_broadcast_urns_id_seq OWNER TO flowartisan;

--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_broadcast_urns_id_seq OWNED BY public.msgs_broadcast_urns.id;


--
-- Name: msgs_broadcastmsgcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_broadcastmsgcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count integer NOT NULL,
    broadcast_id integer NOT NULL
);


ALTER TABLE public.msgs_broadcastmsgcount OWNER TO flowartisan;

--
-- Name: msgs_broadcastmsgcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_broadcastmsgcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_broadcastmsgcount_id_seq OWNER TO flowartisan;

--
-- Name: msgs_broadcastmsgcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_broadcastmsgcount_id_seq OWNED BY public.msgs_broadcastmsgcount.id;


--
-- Name: msgs_exportmessagestask; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_exportmessagestask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    status character varying(1) NOT NULL,
    system_label character varying(1),
    start_date date,
    end_date date,
    created_by_id integer NOT NULL,
    label_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.msgs_exportmessagestask OWNER TO flowartisan;

--
-- Name: msgs_exportmessagestask_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_exportmessagestask_groups (
    id integer NOT NULL,
    exportmessagestask_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.msgs_exportmessagestask_groups OWNER TO flowartisan;

--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_exportmessagestask_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_exportmessagestask_groups_id_seq OWNER TO flowartisan;

--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_exportmessagestask_groups_id_seq OWNED BY public.msgs_exportmessagestask_groups.id;


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_exportmessagestask_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_exportmessagestask_id_seq OWNER TO flowartisan;

--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_exportmessagestask_id_seq OWNED BY public.msgs_exportmessagestask.id;


--
-- Name: msgs_label; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_label (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    label_type character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    folder_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.msgs_label OWNER TO flowartisan;

--
-- Name: msgs_label_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_label_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_label_id_seq OWNER TO flowartisan;

--
-- Name: msgs_label_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_label_id_seq OWNED BY public.msgs_label.id;


--
-- Name: msgs_labelcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_labelcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    is_archived boolean NOT NULL,
    count integer NOT NULL,
    label_id integer NOT NULL
);


ALTER TABLE public.msgs_labelcount OWNER TO flowartisan;

--
-- Name: msgs_labelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_labelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_labelcount_id_seq OWNER TO flowartisan;

--
-- Name: msgs_labelcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_labelcount_id_seq OWNED BY public.msgs_labelcount.id;


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_msg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_msg_id_seq OWNER TO flowartisan;

--
-- Name: msgs_msg_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_msg_id_seq OWNED BY public.msgs_msg.id;


--
-- Name: msgs_msg_labels; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_msg_labels (
    id integer NOT NULL,
    msg_id bigint NOT NULL,
    label_id integer NOT NULL
);


ALTER TABLE public.msgs_msg_labels OWNER TO flowartisan;

--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_msg_labels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_msg_labels_id_seq OWNER TO flowartisan;

--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_msg_labels_id_seq OWNED BY public.msgs_msg_labels.id;


--
-- Name: msgs_systemlabelcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.msgs_systemlabelcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    label_type character varying(1) NOT NULL,
    is_archived boolean NOT NULL,
    count integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.msgs_systemlabelcount OWNER TO flowartisan;

--
-- Name: msgs_systemlabelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.msgs_systemlabelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msgs_systemlabelcount_id_seq OWNER TO flowartisan;

--
-- Name: msgs_systemlabelcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.msgs_systemlabelcount_id_seq OWNED BY public.msgs_systemlabelcount.id;


--
-- Name: notifications_incident; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.notifications_incident (
    id bigint NOT NULL,
    incident_type character varying(20) NOT NULL,
    scope character varying(36) NOT NULL,
    started_on timestamp with time zone NOT NULL,
    ended_on timestamp with time zone,
    channel_id integer,
    org_id integer NOT NULL
);


ALTER TABLE public.notifications_incident OWNER TO flowartisan;

--
-- Name: notifications_incident_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.notifications_incident_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notifications_incident_id_seq OWNER TO flowartisan;

--
-- Name: notifications_incident_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.notifications_incident_id_seq OWNED BY public.notifications_incident.id;


--
-- Name: notifications_notification; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.notifications_notification (
    id bigint NOT NULL,
    notification_type character varying(16) NOT NULL,
    scope character varying(36) NOT NULL,
    is_seen boolean NOT NULL,
    email_status character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    contact_export_id integer,
    contact_import_id integer,
    incident_id bigint,
    message_export_id integer,
    org_id integer NOT NULL,
    results_export_id integer,
    user_id integer NOT NULL
);


ALTER TABLE public.notifications_notification OWNER TO flowartisan;

--
-- Name: notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.notifications_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notifications_notification_id_seq OWNER TO flowartisan;

--
-- Name: notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.notifications_notification_id_seq OWNED BY public.notifications_notification.id;


--
-- Name: notifications_notificationcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.notifications_notificationcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.notifications_notificationcount OWNER TO flowartisan;

--
-- Name: notifications_notificationcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.notifications_notificationcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notifications_notificationcount_id_seq OWNER TO flowartisan;

--
-- Name: notifications_notificationcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.notifications_notificationcount_id_seq OWNED BY public.notifications_notificationcount.id;


--
-- Name: orgs_backuptoken; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_backuptoken (
    id integer NOT NULL,
    token character varying(18) NOT NULL,
    is_used boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_backuptoken OWNER TO flowartisan;

--
-- Name: orgs_backuptoken_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_backuptoken_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_backuptoken_id_seq OWNER TO flowartisan;

--
-- Name: orgs_backuptoken_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_backuptoken_id_seq OWNED BY public.orgs_backuptoken.id;


--
-- Name: orgs_creditalert; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_creditalert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    alert_type character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.orgs_creditalert OWNER TO flowartisan;

--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_creditalert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_creditalert_id_seq OWNER TO flowartisan;

--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_creditalert_id_seq OWNED BY public.orgs_creditalert.id;


--
-- Name: orgs_debit; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_debit (
    id bigint NOT NULL,
    amount integer NOT NULL,
    debit_type character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    beneficiary_id integer,
    created_by_id integer,
    topup_id integer
);


ALTER TABLE public.orgs_debit OWNER TO flowartisan;

--
-- Name: orgs_debit_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_debit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_debit_id_seq OWNER TO flowartisan;

--
-- Name: orgs_debit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_debit_id_seq OWNED BY public.orgs_debit.id;


--
-- Name: orgs_invitation; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_invitation (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(254) NOT NULL,
    secret character varying(64) NOT NULL,
    user_group character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.orgs_invitation OWNER TO flowartisan;

--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_invitation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_invitation_id_seq OWNER TO flowartisan;

--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_invitation_id_seq OWNED BY public.orgs_invitation.id;


--
-- Name: orgs_org; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    name character varying(128) NOT NULL,
    plan character varying(16) NOT NULL,
    plan_start timestamp with time zone,
    plan_end timestamp with time zone,
    stripe_customer character varying(32),
    language character varying(64),
    timezone character varying(63) NOT NULL,
    date_format character varying(1) NOT NULL,
    config text,
    slug character varying(255),
    limits jsonb NOT NULL,
    api_rates jsonb NOT NULL,
    is_anon boolean NOT NULL,
    is_flagged boolean NOT NULL,
    is_suspended boolean NOT NULL,
    uses_topups boolean NOT NULL,
    is_multi_org boolean NOT NULL,
    is_multi_user boolean NOT NULL,
    flow_languages character varying(3)[] NOT NULL,
    brand character varying(128) NOT NULL,
    surveyor_password character varying(128),
    released_on timestamp with time zone,
    deleted_on timestamp with time zone,
    country_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    parent_id integer
);


ALTER TABLE public.orgs_org OWNER TO flowartisan;

--
-- Name: orgs_org_administrators; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org_administrators (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_org_administrators OWNER TO flowartisan;

--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_administrators_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_administrators_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_administrators_id_seq OWNED BY public.orgs_org_administrators.id;


--
-- Name: orgs_org_agents; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org_agents (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_org_agents OWNER TO flowartisan;

--
-- Name: orgs_org_agents_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_agents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_agents_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_agents_id_seq OWNED BY public.orgs_org_agents.id;


--
-- Name: orgs_org_editors; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org_editors (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_org_editors OWNER TO flowartisan;

--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_editors_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_editors_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_editors_id_seq OWNED BY public.orgs_org_editors.id;


--
-- Name: orgs_org_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_id_seq OWNED BY public.orgs_org.id;


--
-- Name: orgs_org_surveyors; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org_surveyors (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_org_surveyors OWNER TO flowartisan;

--
-- Name: orgs_org_surveyors_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_surveyors_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_surveyors_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_surveyors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_surveyors_id_seq OWNED BY public.orgs_org_surveyors.id;


--
-- Name: orgs_org_viewers; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_org_viewers (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_org_viewers OWNER TO flowartisan;

--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_org_viewers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_org_viewers_id_seq OWNER TO flowartisan;

--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_org_viewers_id_seq OWNED BY public.orgs_org_viewers.id;


--
-- Name: orgs_orgactivity; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_orgactivity (
    id integer NOT NULL,
    day date NOT NULL,
    contact_count integer NOT NULL,
    active_contact_count integer NOT NULL,
    outgoing_count integer NOT NULL,
    incoming_count integer NOT NULL,
    plan_active_contact_count integer,
    org_id integer NOT NULL
);


ALTER TABLE public.orgs_orgactivity OWNER TO flowartisan;

--
-- Name: orgs_orgactivity_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_orgactivity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_orgactivity_id_seq OWNER TO flowartisan;

--
-- Name: orgs_orgactivity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_orgactivity_id_seq OWNED BY public.orgs_orgactivity.id;


--
-- Name: orgs_orgmembership; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_orgmembership (
    id integer NOT NULL,
    role_code character varying(1) NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.orgs_orgmembership OWNER TO flowartisan;

--
-- Name: orgs_orgmembership_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_orgmembership_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_orgmembership_id_seq OWNER TO flowartisan;

--
-- Name: orgs_orgmembership_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_orgmembership_id_seq OWNED BY public.orgs_orgmembership.id;


--
-- Name: orgs_topup; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_topup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    price integer,
    credits integer NOT NULL,
    expires_on timestamp with time zone NOT NULL,
    stripe_charge character varying(32),
    comment character varying(255),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.orgs_topup OWNER TO flowartisan;

--
-- Name: orgs_topup_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_topup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_topup_id_seq OWNER TO flowartisan;

--
-- Name: orgs_topup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_topup_id_seq OWNED BY public.orgs_topup.id;


--
-- Name: orgs_topupcredits; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_topupcredits (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    used integer NOT NULL,
    topup_id integer NOT NULL
);


ALTER TABLE public.orgs_topupcredits OWNER TO flowartisan;

--
-- Name: orgs_topupcredits_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_topupcredits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_topupcredits_id_seq OWNER TO flowartisan;

--
-- Name: orgs_topupcredits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_topupcredits_id_seq OWNED BY public.orgs_topupcredits.id;


--
-- Name: orgs_usersettings; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.orgs_usersettings (
    id integer NOT NULL,
    language character varying(8) NOT NULL,
    otp_secret character varying(16) NOT NULL,
    two_factor_enabled boolean NOT NULL,
    last_auth_on timestamp with time zone,
    external_id character varying(128),
    verification_token character varying(64),
    user_id integer NOT NULL,
    team_id integer
);


ALTER TABLE public.orgs_usersettings OWNER TO flowartisan;

--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.orgs_usersettings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orgs_usersettings_id_seq OWNER TO flowartisan;

--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.orgs_usersettings_id_seq OWNED BY public.orgs_usersettings.id;


--
-- Name: policies_consent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.policies_consent (
    id integer NOT NULL,
    revoked_on timestamp with time zone,
    created_on timestamp with time zone NOT NULL,
    policy_id integer NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.policies_consent OWNER TO flowartisan;

--
-- Name: policies_consent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.policies_consent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.policies_consent_id_seq OWNER TO flowartisan;

--
-- Name: policies_consent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.policies_consent_id_seq OWNED BY public.policies_consent.id;


--
-- Name: policies_policy; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.policies_policy (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    policy_type character varying(16) NOT NULL,
    body text NOT NULL,
    summary text,
    requires_consent boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


ALTER TABLE public.policies_policy OWNER TO flowartisan;

--
-- Name: policies_policy_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.policies_policy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.policies_policy_id_seq OWNER TO flowartisan;

--
-- Name: policies_policy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.policies_policy_id_seq OWNED BY public.policies_policy.id;


--
-- Name: public_lead; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.public_lead (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(254) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


ALTER TABLE public.public_lead OWNER TO flowartisan;

--
-- Name: public_lead_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.public_lead_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.public_lead_id_seq OWNER TO flowartisan;

--
-- Name: public_lead_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.public_lead_id_seq OWNED BY public.public_lead.id;


--
-- Name: public_video; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.public_video (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    summary text NOT NULL,
    description text NOT NULL,
    vimeo_id character varying(255) NOT NULL,
    "order" integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


ALTER TABLE public.public_video OWNER TO flowartisan;

--
-- Name: public_video_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.public_video_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.public_video_id_seq OWNER TO flowartisan;

--
-- Name: public_video_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.public_video_id_seq OWNED BY public.public_video.id;


--
-- Name: request_logs_httplog; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.request_logs_httplog (
    id integer NOT NULL,
    log_type character varying(32) NOT NULL,
    url character varying(2048) NOT NULL,
    status_code integer,
    request text NOT NULL,
    response text,
    request_time integer NOT NULL,
    num_retries integer,
    created_on timestamp with time zone NOT NULL,
    is_error boolean NOT NULL,
    airtime_transfer_id integer,
    channel_id integer,
    classifier_id integer,
    flow_id integer,
    org_id integer NOT NULL,
    ticketer_id integer
);


ALTER TABLE public.request_logs_httplog OWNER TO flowartisan;

--
-- Name: request_logs_httplog_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.request_logs_httplog_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.request_logs_httplog_id_seq OWNER TO flowartisan;

--
-- Name: request_logs_httplog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.request_logs_httplog_id_seq OWNED BY public.request_logs_httplog.id;


--
-- Name: schedules_schedule; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.schedules_schedule (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    repeat_period character varying(1) NOT NULL,
    repeat_hour_of_day integer,
    repeat_minute_of_hour integer,
    repeat_day_of_month integer,
    repeat_days_of_week character varying(7),
    next_fire timestamp with time zone,
    last_fire timestamp with time zone,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.schedules_schedule OWNER TO flowartisan;

--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.schedules_schedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.schedules_schedule_id_seq OWNER TO flowartisan;

--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.schedules_schedule_id_seq OWNED BY public.schedules_schedule.id;


--
-- Name: templates_template; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.templates_template (
    id integer NOT NULL,
    uuid uuid NOT NULL,
    name character varying(512) NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    created_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL
);


ALTER TABLE public.templates_template OWNER TO flowartisan;

--
-- Name: templates_template_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.templates_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.templates_template_id_seq OWNER TO flowartisan;

--
-- Name: templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.templates_template_id_seq OWNED BY public.templates_template.id;


--
-- Name: templates_templatetranslation; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.templates_templatetranslation (
    id integer NOT NULL,
    content text NOT NULL,
    variable_count integer NOT NULL,
    status character varying(1) NOT NULL,
    language character varying(6) NOT NULL,
    country character varying(2),
    namespace character varying(36) NOT NULL,
    external_id character varying(64),
    is_active boolean NOT NULL,
    channel_id integer NOT NULL,
    template_id integer NOT NULL
);


ALTER TABLE public.templates_templatetranslation OWNER TO flowartisan;

--
-- Name: templates_templatetranslation_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.templates_templatetranslation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.templates_templatetranslation_id_seq OWNER TO flowartisan;

--
-- Name: templates_templatetranslation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.templates_templatetranslation_id_seq OWNED BY public.templates_templatetranslation.id;


--
-- Name: tickets_team; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_team (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    name character varying(64) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.tickets_team OWNER TO flowartisan;

--
-- Name: tickets_team_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_team_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_team_id_seq OWNER TO flowartisan;

--
-- Name: tickets_team_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_team_id_seq OWNED BY public.tickets_team.id;


--
-- Name: tickets_team_topics; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_team_topics (
    id integer NOT NULL,
    team_id integer NOT NULL,
    topic_id integer NOT NULL
);


ALTER TABLE public.tickets_team_topics OWNER TO flowartisan;

--
-- Name: tickets_team_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_team_topics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_team_topics_id_seq OWNER TO flowartisan;

--
-- Name: tickets_team_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_team_topics_id_seq OWNED BY public.tickets_team_topics.id;


--
-- Name: tickets_ticket; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticket (
    id integer NOT NULL,
    uuid uuid NOT NULL,
    body text NOT NULL,
    external_id character varying(255),
    config jsonb,
    status character varying(1) NOT NULL,
    opened_on timestamp with time zone NOT NULL,
    closed_on timestamp with time zone,
    modified_on timestamp with time zone NOT NULL,
    last_activity_on timestamp with time zone NOT NULL,
    assignee_id integer,
    contact_id integer NOT NULL,
    org_id integer NOT NULL,
    ticketer_id integer NOT NULL,
    topic_id integer NOT NULL,
    replied_on timestamp with time zone
);


ALTER TABLE public.tickets_ticket OWNER TO flowartisan;

--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticket_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticket_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticket_id_seq OWNED BY public.tickets_ticket.id;


--
-- Name: tickets_ticketcount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticketcount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    status character varying(1) NOT NULL,
    count integer NOT NULL,
    assignee_id integer,
    org_id integer NOT NULL
);


ALTER TABLE public.tickets_ticketcount OWNER TO flowartisan;

--
-- Name: tickets_ticketcount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticketcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticketcount_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticketcount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticketcount_id_seq OWNED BY public.tickets_ticketcount.id;


--
-- Name: tickets_ticketdailycount; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticketdailycount (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count_type character varying(1) NOT NULL,
    scope character varying(32) NOT NULL,
    count integer NOT NULL,
    day date NOT NULL
);


ALTER TABLE public.tickets_ticketdailycount OWNER TO flowartisan;

--
-- Name: tickets_ticketdailycount_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticketdailycount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticketdailycount_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticketdailycount_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticketdailycount_id_seq OWNED BY public.tickets_ticketdailycount.id;


--
-- Name: tickets_ticketdailytiming; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticketdailytiming (
    id bigint NOT NULL,
    is_squashed boolean NOT NULL,
    count_type character varying(1) NOT NULL,
    scope character varying(32) NOT NULL,
    count integer NOT NULL,
    day date NOT NULL,
    seconds bigint NOT NULL
);


ALTER TABLE public.tickets_ticketdailytiming OWNER TO flowartisan;

--
-- Name: tickets_ticketdailytiming_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticketdailytiming_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticketdailytiming_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticketdailytiming_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticketdailytiming_id_seq OWNED BY public.tickets_ticketdailytiming.id;


--
-- Name: tickets_ticketer; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticketer (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    ticketer_type character varying(16) NOT NULL,
    name character varying(64) NOT NULL,
    config jsonb NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.tickets_ticketer OWNER TO flowartisan;

--
-- Name: tickets_ticketer_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticketer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticketer_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticketer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticketer_id_seq OWNED BY public.tickets_ticketer.id;


--
-- Name: tickets_ticketevent; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_ticketevent (
    id integer NOT NULL,
    event_type character varying(1) NOT NULL,
    note text,
    created_on timestamp with time zone NOT NULL,
    assignee_id integer,
    contact_id integer NOT NULL,
    created_by_id integer,
    org_id integer NOT NULL,
    ticket_id integer NOT NULL,
    topic_id integer
);


ALTER TABLE public.tickets_ticketevent OWNER TO flowartisan;

--
-- Name: tickets_ticketevent_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_ticketevent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_ticketevent_id_seq OWNER TO flowartisan;

--
-- Name: tickets_ticketevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_ticketevent_id_seq OWNED BY public.tickets_ticketevent.id;


--
-- Name: tickets_topic; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.tickets_topic (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid uuid NOT NULL,
    name character varying(64) NOT NULL,
    is_default boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_system boolean NOT NULL
);


ALTER TABLE public.tickets_topic OWNER TO flowartisan;

--
-- Name: tickets_topic_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.tickets_topic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tickets_topic_id_seq OWNER TO flowartisan;

--
-- Name: tickets_topic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.tickets_topic_id_seq OWNED BY public.tickets_topic.id;


--
-- Name: triggers_trigger; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.triggers_trigger (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    trigger_type character varying(1) NOT NULL,
    is_archived boolean NOT NULL,
    keyword character varying(16),
    referrer_id character varying(255),
    match_type character varying(1),
    channel_id integer,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    schedule_id integer
);


ALTER TABLE public.triggers_trigger OWNER TO flowartisan;

--
-- Name: triggers_trigger_contacts; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.triggers_trigger_contacts (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contact_id integer NOT NULL
);


ALTER TABLE public.triggers_trigger_contacts OWNER TO flowartisan;

--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.triggers_trigger_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.triggers_trigger_contacts_id_seq OWNER TO flowartisan;

--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.triggers_trigger_contacts_id_seq OWNED BY public.triggers_trigger_contacts.id;


--
-- Name: triggers_trigger_exclude_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.triggers_trigger_exclude_groups (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.triggers_trigger_exclude_groups OWNER TO flowartisan;

--
-- Name: triggers_trigger_exclude_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.triggers_trigger_exclude_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.triggers_trigger_exclude_groups_id_seq OWNER TO flowartisan;

--
-- Name: triggers_trigger_exclude_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.triggers_trigger_exclude_groups_id_seq OWNED BY public.triggers_trigger_exclude_groups.id;


--
-- Name: triggers_trigger_groups; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.triggers_trigger_groups (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


ALTER TABLE public.triggers_trigger_groups OWNER TO flowartisan;

--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.triggers_trigger_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.triggers_trigger_groups_id_seq OWNER TO flowartisan;

--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.triggers_trigger_groups_id_seq OWNED BY public.triggers_trigger_groups.id;


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.triggers_trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.triggers_trigger_id_seq OWNER TO flowartisan;

--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.triggers_trigger_id_seq OWNED BY public.triggers_trigger.id;


--
-- Name: users_failedlogin; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.users_failedlogin (
    id integer NOT NULL,
    failed_on timestamp with time zone NOT NULL,
    username character varying(256) NOT NULL
);


ALTER TABLE public.users_failedlogin OWNER TO flowartisan;

--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.users_failedlogin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_failedlogin_id_seq OWNER TO flowartisan;

--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.users_failedlogin_id_seq OWNED BY public.users_failedlogin.id;


--
-- Name: users_passwordhistory; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.users_passwordhistory (
    id integer NOT NULL,
    password character varying(255) NOT NULL,
    set_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.users_passwordhistory OWNER TO flowartisan;

--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.users_passwordhistory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_passwordhistory_id_seq OWNER TO flowartisan;

--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.users_passwordhistory_id_seq OWNED BY public.users_passwordhistory.id;


--
-- Name: users_recoverytoken; Type: TABLE; Schema: public; Owner: flowartisan
--

CREATE TABLE public.users_recoverytoken (
    id integer NOT NULL,
    token character varying(32) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.users_recoverytoken OWNER TO flowartisan;

--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE; Schema: public; Owner: flowartisan
--

CREATE SEQUENCE public.users_recoverytoken_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_recoverytoken_id_seq OWNER TO flowartisan;

--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: flowartisan
--

ALTER SEQUENCE public.users_recoverytoken_id_seq OWNED BY public.users_recoverytoken.id;


--
-- Name: airtime_airtimetransfer id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.airtime_airtimetransfer ALTER COLUMN id SET DEFAULT nextval('public.airtime_airtimetransfer_id_seq'::regclass);


--
-- Name: api_resthook id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthook ALTER COLUMN id SET DEFAULT nextval('public.api_resthook_id_seq'::regclass);


--
-- Name: api_resthooksubscriber id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthooksubscriber ALTER COLUMN id SET DEFAULT nextval('public.api_resthooksubscriber_id_seq'::regclass);


--
-- Name: api_webhookevent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_webhookevent ALTER COLUMN id SET DEFAULT nextval('public.api_webhookevent_id_seq'::regclass);


--
-- Name: apks_apk id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.apks_apk ALTER COLUMN id SET DEFAULT nextval('public.apks_apk_id_seq'::regclass);


--
-- Name: archives_archive id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.archives_archive ALTER COLUMN id SET DEFAULT nextval('public.archives_archive_id_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group ALTER COLUMN id SET DEFAULT nextval('public.auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_permission ALTER COLUMN id SET DEFAULT nextval('public.auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user ALTER COLUMN id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_groups ALTER COLUMN id SET DEFAULT nextval('public.auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_user_user_permissions_id_seq'::regclass);


--
-- Name: campaigns_campaign id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign ALTER COLUMN id SET DEFAULT nextval('public.campaigns_campaign_id_seq'::regclass);


--
-- Name: campaigns_campaignevent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent ALTER COLUMN id SET DEFAULT nextval('public.campaigns_campaignevent_id_seq'::regclass);


--
-- Name: campaigns_eventfire id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_eventfire ALTER COLUMN id SET DEFAULT nextval('public.campaigns_eventfire_id_seq'::regclass);


--
-- Name: channels_alert id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert ALTER COLUMN id SET DEFAULT nextval('public.channels_alert_id_seq'::regclass);


--
-- Name: channels_channel id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel ALTER COLUMN id SET DEFAULT nextval('public.channels_channel_id_seq'::regclass);


--
-- Name: channels_channelconnection id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection ALTER COLUMN id SET DEFAULT nextval('public.channels_channelconnection_id_seq'::regclass);


--
-- Name: channels_channelcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelcount ALTER COLUMN id SET DEFAULT nextval('public.channels_channelcount_id_seq'::regclass);


--
-- Name: channels_channelevent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent ALTER COLUMN id SET DEFAULT nextval('public.channels_channelevent_id_seq'::regclass);


--
-- Name: channels_channellog id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channellog ALTER COLUMN id SET DEFAULT nextval('public.channels_channellog_id_seq'::regclass);


--
-- Name: channels_syncevent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_syncevent ALTER COLUMN id SET DEFAULT nextval('public.channels_syncevent_id_seq'::regclass);


--
-- Name: classifiers_classifier id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier ALTER COLUMN id SET DEFAULT nextval('public.classifiers_classifier_id_seq'::regclass);


--
-- Name: classifiers_intent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_intent ALTER COLUMN id SET DEFAULT nextval('public.classifiers_intent_id_seq'::regclass);


--
-- Name: contacts_contact id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact ALTER COLUMN id SET DEFAULT nextval('public.contacts_contact_id_seq'::regclass);


--
-- Name: contacts_contactfield id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactfield_id_seq'::regclass);


--
-- Name: contacts_contactgroup id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactgroup_id_seq'::regclass);


--
-- Name: contacts_contactgroup_contacts id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_contacts ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactgroup_contacts_id_seq'::regclass);


--
-- Name: contacts_contactgroup_query_fields id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_query_fields ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactgroup_query_fields_id_seq'::regclass);


--
-- Name: contacts_contactgroupcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroupcount ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactgroupcount_id_seq'::regclass);


--
-- Name: contacts_contactimport id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactimport_id_seq'::regclass);


--
-- Name: contacts_contactimportbatch id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimportbatch ALTER COLUMN id SET DEFAULT nextval('public.contacts_contactimportbatch_id_seq'::regclass);


--
-- Name: contacts_contacturn id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn ALTER COLUMN id SET DEFAULT nextval('public.contacts_contacturn_id_seq'::regclass);


--
-- Name: contacts_exportcontactstask id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask ALTER COLUMN id SET DEFAULT nextval('public.contacts_exportcontactstask_id_seq'::regclass);


--
-- Name: contacts_exportcontactstask_group_memberships id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask_group_memberships ALTER COLUMN id SET DEFAULT nextval('public.contacts_exportcontactstask_group_memberships_id_seq'::regclass);


--
-- Name: csv_imports_importtask id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.csv_imports_importtask ALTER COLUMN id SET DEFAULT nextval('public.csv_imports_importtask_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Name: django_site id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_site ALTER COLUMN id SET DEFAULT nextval('public.django_site_id_seq'::regclass);


--
-- Name: flows_exportflowresultstask id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask ALTER COLUMN id SET DEFAULT nextval('public.flows_exportflowresultstask_id_seq'::regclass);


--
-- Name: flows_exportflowresultstask_flows id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask_flows ALTER COLUMN id SET DEFAULT nextval('public.flows_exportflowresultstask_flows_id_seq'::regclass);


--
-- Name: flows_flow id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_id_seq'::regclass);


--
-- Name: flows_flow_channel_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_channel_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_channel_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_classifier_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_classifier_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_classifier_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_field_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_field_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_field_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_flow_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_flow_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_flow_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_global_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_global_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_global_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_group_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_group_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_group_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_label_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_label_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_label_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_labels id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_labels ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_labels_id_seq'::regclass);


--
-- Name: flows_flow_template_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_template_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_template_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_ticketer_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_ticketer_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_ticketer_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_topic_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_topic_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_topic_dependencies_id_seq'::regclass);


--
-- Name: flows_flow_user_dependencies id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_user_dependencies ALTER COLUMN id SET DEFAULT nextval('public.flows_flow_user_dependencies_id_seq'::regclass);


--
-- Name: flows_flowcategorycount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowcategorycount ALTER COLUMN id SET DEFAULT nextval('public.flows_flowcategorycount_id_seq'::regclass);


--
-- Name: flows_flowlabel id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel ALTER COLUMN id SET DEFAULT nextval('public.flows_flowlabel_id_seq'::regclass);


--
-- Name: flows_flownodecount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flownodecount ALTER COLUMN id SET DEFAULT nextval('public.flows_flownodecount_id_seq'::regclass);


--
-- Name: flows_flowpathcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowpathcount ALTER COLUMN id SET DEFAULT nextval('public.flows_flowpathcount_id_seq'::regclass);


--
-- Name: flows_flowrevision id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrevision ALTER COLUMN id SET DEFAULT nextval('public.flows_flowrevision_id_seq'::regclass);


--
-- Name: flows_flowrun id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun ALTER COLUMN id SET DEFAULT nextval('public.flows_flowrun_id_seq'::regclass);


--
-- Name: flows_flowruncount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowruncount ALTER COLUMN id SET DEFAULT nextval('public.flows_flowruncount_id_seq'::regclass);


--
-- Name: flows_flowsession id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession ALTER COLUMN id SET DEFAULT nextval('public.flows_flowsession_id_seq'::regclass);


--
-- Name: flows_flowstart id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart ALTER COLUMN id SET DEFAULT nextval('public.flows_flowstart_id_seq'::regclass);


--
-- Name: flows_flowstart_connections id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_connections ALTER COLUMN id SET DEFAULT nextval('public.flows_flowstart_connections_id_seq'::regclass);


--
-- Name: flows_flowstart_contacts id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_contacts ALTER COLUMN id SET DEFAULT nextval('public.flows_flowstart_contacts_id_seq'::regclass);


--
-- Name: flows_flowstart_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_groups ALTER COLUMN id SET DEFAULT nextval('public.flows_flowstart_groups_id_seq'::regclass);


--
-- Name: flows_flowstartcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstartcount ALTER COLUMN id SET DEFAULT nextval('public.flows_flowstartcount_id_seq'::regclass);


--
-- Name: globals_global id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global ALTER COLUMN id SET DEFAULT nextval('public.globals_global_id_seq'::regclass);


--
-- Name: locations_adminboundary id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_adminboundary ALTER COLUMN id SET DEFAULT nextval('public.locations_adminboundary_id_seq'::regclass);


--
-- Name: locations_boundaryalias id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias ALTER COLUMN id SET DEFAULT nextval('public.locations_boundaryalias_id_seq'::regclass);


--
-- Name: msgs_broadcast id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast ALTER COLUMN id SET DEFAULT nextval('public.msgs_broadcast_id_seq'::regclass);


--
-- Name: msgs_broadcast_contacts id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_contacts ALTER COLUMN id SET DEFAULT nextval('public.msgs_broadcast_contacts_id_seq'::regclass);


--
-- Name: msgs_broadcast_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_groups ALTER COLUMN id SET DEFAULT nextval('public.msgs_broadcast_groups_id_seq'::regclass);


--
-- Name: msgs_broadcast_urns id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_urns ALTER COLUMN id SET DEFAULT nextval('public.msgs_broadcast_urns_id_seq'::regclass);


--
-- Name: msgs_broadcastmsgcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcastmsgcount ALTER COLUMN id SET DEFAULT nextval('public.msgs_broadcastmsgcount_id_seq'::regclass);


--
-- Name: msgs_exportmessagestask id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask ALTER COLUMN id SET DEFAULT nextval('public.msgs_exportmessagestask_id_seq'::regclass);


--
-- Name: msgs_exportmessagestask_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask_groups ALTER COLUMN id SET DEFAULT nextval('public.msgs_exportmessagestask_groups_id_seq'::regclass);


--
-- Name: msgs_label id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label ALTER COLUMN id SET DEFAULT nextval('public.msgs_label_id_seq'::regclass);


--
-- Name: msgs_labelcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_labelcount ALTER COLUMN id SET DEFAULT nextval('public.msgs_labelcount_id_seq'::regclass);


--
-- Name: msgs_msg id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg ALTER COLUMN id SET DEFAULT nextval('public.msgs_msg_id_seq'::regclass);


--
-- Name: msgs_msg_labels id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg_labels ALTER COLUMN id SET DEFAULT nextval('public.msgs_msg_labels_id_seq'::regclass);


--
-- Name: msgs_systemlabelcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_systemlabelcount ALTER COLUMN id SET DEFAULT nextval('public.msgs_systemlabelcount_id_seq'::regclass);


--
-- Name: notifications_incident id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_incident ALTER COLUMN id SET DEFAULT nextval('public.notifications_incident_id_seq'::regclass);


--
-- Name: notifications_notification id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification ALTER COLUMN id SET DEFAULT nextval('public.notifications_notification_id_seq'::regclass);


--
-- Name: notifications_notificationcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notificationcount ALTER COLUMN id SET DEFAULT nextval('public.notifications_notificationcount_id_seq'::regclass);


--
-- Name: orgs_backuptoken id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_backuptoken ALTER COLUMN id SET DEFAULT nextval('public.orgs_backuptoken_id_seq'::regclass);


--
-- Name: orgs_creditalert id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_creditalert ALTER COLUMN id SET DEFAULT nextval('public.orgs_creditalert_id_seq'::regclass);


--
-- Name: orgs_debit id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_debit ALTER COLUMN id SET DEFAULT nextval('public.orgs_debit_id_seq'::regclass);


--
-- Name: orgs_invitation id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation ALTER COLUMN id SET DEFAULT nextval('public.orgs_invitation_id_seq'::regclass);


--
-- Name: orgs_org id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_id_seq'::regclass);


--
-- Name: orgs_org_administrators id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_administrators ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_administrators_id_seq'::regclass);


--
-- Name: orgs_org_agents id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_agents ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_agents_id_seq'::regclass);


--
-- Name: orgs_org_editors id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_editors ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_editors_id_seq'::regclass);


--
-- Name: orgs_org_surveyors id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_surveyors ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_surveyors_id_seq'::regclass);


--
-- Name: orgs_org_viewers id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_viewers ALTER COLUMN id SET DEFAULT nextval('public.orgs_org_viewers_id_seq'::regclass);


--
-- Name: orgs_orgactivity id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgactivity ALTER COLUMN id SET DEFAULT nextval('public.orgs_orgactivity_id_seq'::regclass);


--
-- Name: orgs_orgmembership id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgmembership ALTER COLUMN id SET DEFAULT nextval('public.orgs_orgmembership_id_seq'::regclass);


--
-- Name: orgs_topup id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topup ALTER COLUMN id SET DEFAULT nextval('public.orgs_topup_id_seq'::regclass);


--
-- Name: orgs_topupcredits id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topupcredits ALTER COLUMN id SET DEFAULT nextval('public.orgs_topupcredits_id_seq'::regclass);


--
-- Name: orgs_usersettings id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_usersettings ALTER COLUMN id SET DEFAULT nextval('public.orgs_usersettings_id_seq'::regclass);


--
-- Name: policies_consent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_consent ALTER COLUMN id SET DEFAULT nextval('public.policies_consent_id_seq'::regclass);


--
-- Name: policies_policy id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_policy ALTER COLUMN id SET DEFAULT nextval('public.policies_policy_id_seq'::regclass);


--
-- Name: public_lead id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_lead ALTER COLUMN id SET DEFAULT nextval('public.public_lead_id_seq'::regclass);


--
-- Name: public_video id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_video ALTER COLUMN id SET DEFAULT nextval('public.public_video_id_seq'::regclass);


--
-- Name: request_logs_httplog id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog ALTER COLUMN id SET DEFAULT nextval('public.request_logs_httplog_id_seq'::regclass);


--
-- Name: schedules_schedule id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.schedules_schedule ALTER COLUMN id SET DEFAULT nextval('public.schedules_schedule_id_seq'::regclass);


--
-- Name: templates_template id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_template ALTER COLUMN id SET DEFAULT nextval('public.templates_template_id_seq'::regclass);


--
-- Name: templates_templatetranslation id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_templatetranslation ALTER COLUMN id SET DEFAULT nextval('public.templates_templatetranslation_id_seq'::regclass);


--
-- Name: tickets_team id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team ALTER COLUMN id SET DEFAULT nextval('public.tickets_team_id_seq'::regclass);


--
-- Name: tickets_team_topics id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team_topics ALTER COLUMN id SET DEFAULT nextval('public.tickets_team_topics_id_seq'::regclass);


--
-- Name: tickets_ticket id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticket_id_seq'::regclass);


--
-- Name: tickets_ticketcount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketcount ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticketcount_id_seq'::regclass);


--
-- Name: tickets_ticketdailycount id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketdailycount ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticketdailycount_id_seq'::regclass);


--
-- Name: tickets_ticketdailytiming id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketdailytiming ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticketdailytiming_id_seq'::regclass);


--
-- Name: tickets_ticketer id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticketer_id_seq'::regclass);


--
-- Name: tickets_ticketevent id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent ALTER COLUMN id SET DEFAULT nextval('public.tickets_ticketevent_id_seq'::regclass);


--
-- Name: tickets_topic id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic ALTER COLUMN id SET DEFAULT nextval('public.tickets_topic_id_seq'::regclass);


--
-- Name: triggers_trigger id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger ALTER COLUMN id SET DEFAULT nextval('public.triggers_trigger_id_seq'::regclass);


--
-- Name: triggers_trigger_contacts id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_contacts ALTER COLUMN id SET DEFAULT nextval('public.triggers_trigger_contacts_id_seq'::regclass);


--
-- Name: triggers_trigger_exclude_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_exclude_groups ALTER COLUMN id SET DEFAULT nextval('public.triggers_trigger_exclude_groups_id_seq'::regclass);


--
-- Name: triggers_trigger_groups id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_groups ALTER COLUMN id SET DEFAULT nextval('public.triggers_trigger_groups_id_seq'::regclass);


--
-- Name: users_failedlogin id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_failedlogin ALTER COLUMN id SET DEFAULT nextval('public.users_failedlogin_id_seq'::regclass);


--
-- Name: users_passwordhistory id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_passwordhistory ALTER COLUMN id SET DEFAULT nextval('public.users_passwordhistory_id_seq'::regclass);


--
-- Name: users_recoverytoken id; Type: DEFAULT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_recoverytoken ALTER COLUMN id SET DEFAULT nextval('public.users_recoverytoken_id_seq'::regclass);


--
-- Data for Name: airtime_airtimetransfer; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.airtime_airtimetransfer (id, status, recipient, sender, currency, desired_amount, actual_amount, created_on, contact_id, org_id) FROM stdin;
\.


--
-- Data for Name: api_apitoken; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.api_apitoken (is_active, key, created, org_id, role_id, user_id) FROM stdin;
\.


--
-- Data for Name: api_resthook; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.api_resthook (id, is_active, created_on, modified_on, slug, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: api_resthooksubscriber; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.api_resthooksubscriber (id, is_active, created_on, modified_on, target_url, created_by_id, modified_by_id, resthook_id) FROM stdin;
\.


--
-- Data for Name: api_webhookevent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.api_webhookevent (id, data, action, created_on, org_id, resthook_id) FROM stdin;
\.


--
-- Data for Name: apks_apk; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.apks_apk (id, apk_type, apk_file, version, pack, description, created_on) FROM stdin;
\.


--
-- Data for Name: archives_archive; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.archives_archive (id, archive_type, created_on, period, start_date, record_count, size, hash, url, needs_deletion, build_time, deleted_on, org_id, rollup_id) FROM stdin;
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_group (id, name) FROM stdin;
1	Service Users
2	Alpha
3	Beta
4	Dashboard
5	Surveyors
6	Granters
7	Customer Support
8	Administrators
9	Editors
10	Viewers
11	Agents
12	Prometheus
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
1	1	941
2	1	649
3	3	753
4	4	888
5	5	844
6	5	867
7	5	861
8	5	939
9	5	877
10	5	883
11	5	913
12	5	915
13	5	963
14	6	893
15	7	429
16	7	433
17	7	431
18	7	795
19	7	926
20	7	610
21	7	635
22	7	849
23	7	565
24	7	947
25	7	957
26	7	727
27	7	962
28	7	888
29	7	517
30	7	893
31	7	899
32	7	516
33	7	911
34	7	913
35	7	519
36	7	983
37	7	521
38	7	563
39	7	561
40	7	489
41	7	491
42	7	984
43	7	985
44	8	828
45	8	825
46	8	829
47	8	830
48	8	832
49	8	831
50	8	871
51	8	434
52	8	437
53	8	438
54	8	873
55	8	435
56	8	872
57	8	436
58	8	836
59	8	833
60	8	835
61	8	834
62	8	794
63	8	797
64	8	798
65	8	837
66	8	795
67	8	796
68	8	838
69	8	799
70	8	802
71	8	803
72	8	800
73	8	801
74	8	840
75	8	839
76	8	465
77	8	467
78	8	468
79	8	842
80	8	841
81	8	843
82	8	844
83	8	845
84	8	846
85	8	847
86	8	848
87	8	564
88	8	567
89	8	850
90	8	852
91	8	853
92	8	568
93	8	854
94	8	855
95	8	565
96	8	856
97	8	857
98	8	858
99	8	851
100	8	566
101	8	859
102	8	860
103	8	861
104	8	569
105	8	572
106	8	865
107	8	866
108	8	862
109	8	573
110	8	863
111	8	570
112	8	571
113	8	864
114	8	867
115	8	574
116	8	577
117	8	578
118	8	868
119	8	575
120	8	576
121	8	584
122	8	587
123	8	588
124	8	869
125	8	585
126	8	586
127	8	409
128	8	412
129	8	413
130	8	410
131	8	411
132	8	874
133	8	474
134	8	477
135	8	478
136	8	475
137	8	875
138	8	476
139	8	809
140	8	812
141	8	813
142	8	810
143	8	870
144	8	811
145	8	876
146	8	877
147	8	878
148	8	879
149	8	684
150	8	687
151	8	688
152	8	685
153	8	686
154	8	674
155	8	677
156	8	678
157	8	675
158	8	676
159	8	880
160	8	881
161	8	882
162	8	883
163	8	884
164	8	887
165	8	888
166	8	889
167	8	890
168	8	891
169	8	892
170	8	894
171	8	895
172	8	898
173	8	900
174	8	901
175	8	902
176	8	903
177	8	904
178	8	905
179	8	906
180	8	907
181	8	908
182	8	909
183	8	910
184	8	913
185	8	914
186	8	916
187	8	918
188	8	919
189	8	920
190	8	921
191	8	922
192	8	523
193	8	520
194	8	923
195	8	924
196	8	925
197	8	926
198	8	609
199	8	927
200	8	928
201	8	930
202	8	612
203	8	613
204	8	931
205	8	610
206	8	611
207	8	933
208	8	934
209	8	624
210	8	627
211	8	628
212	8	625
213	8	626
214	8	638
215	8	635
216	8	932
217	8	936
218	8	937
219	8	938
220	8	939
221	8	940
222	8	941
223	8	942
224	8	943
225	8	944
226	8	945
227	8	946
228	8	694
229	8	697
230	8	950
231	8	947
232	8	948
233	8	952
234	8	949
235	8	953
236	8	951
237	8	698
238	8	954
239	8	695
240	8	955
241	8	956
242	8	957
243	8	958
244	8	959
245	8	696
246	8	960
247	8	961
248	8	935
249	8	739
250	8	742
251	8	743
252	8	740
253	8	741
254	8	704
255	8	707
256	8	708
257	8	705
258	8	706
259	8	727
260	8	499
261	8	502
262	8	503
263	8	500
264	8	501
265	8	975
266	8	639
267	8	642
268	8	976
269	8	643
270	8	640
271	8	977
272	8	978
273	8	979
274	8	980
275	8	641
276	8	981
277	8	644
278	8	647
279	8	982
280	8	648
281	8	645
282	8	646
283	8	963
284	8	964
285	8	965
286	8	652
287	8	966
288	8	967
289	8	968
290	8	969
291	8	970
292	8	971
293	8	972
294	8	973
295	8	974
296	8	651
297	8	490
298	8	493
299	8	986
300	8	463
301	8	460
302	8	987
303	8	990
304	8	991
305	8	992
306	8	993
307	8	749
308	8	752
309	8	996
310	8	753
311	8	994
312	8	995
313	8	750
314	8	751
315	8	997
316	8	999
317	8	998
318	8	764
319	8	767
320	8	768
321	8	765
322	8	766
323	8	1000
324	8	754
325	8	757
326	8	758
327	8	755
328	8	756
329	8	1001
330	8	789
331	8	792
332	8	793
333	8	1003
334	8	790
335	8	1002
336	8	791
337	9	829
338	9	830
339	9	832
340	9	831
341	9	458
342	9	455
343	9	871
344	9	434
345	9	437
346	9	438
347	9	873
348	9	435
349	9	872
350	9	436
351	9	828
352	9	825
353	9	836
354	9	833
355	9	835
356	9	834
357	9	794
358	9	797
359	9	798
360	9	837
361	9	795
362	9	796
363	9	838
364	9	799
365	9	802
366	9	803
367	9	800
368	9	801
369	9	840
370	9	465
371	9	468
372	9	842
373	9	843
374	9	844
375	9	845
376	9	846
377	9	847
378	9	848
379	9	564
380	9	567
381	9	850
382	9	852
383	9	853
384	9	568
385	9	854
386	9	855
387	9	565
388	9	856
389	9	857
390	9	858
391	9	851
392	9	566
393	9	859
394	9	860
395	9	861
396	9	569
397	9	572
398	9	865
399	9	866
400	9	862
401	9	573
402	9	863
403	9	570
404	9	571
405	9	864
406	9	867
407	9	574
408	9	577
409	9	578
410	9	868
411	9	575
412	9	576
413	9	584
414	9	587
415	9	588
416	9	869
417	9	585
418	9	586
419	9	409
420	9	412
421	9	413
422	9	410
423	9	411
424	9	809
425	9	812
426	9	813
427	9	810
428	9	870
429	9	811
430	9	874
431	9	876
432	9	877
433	9	878
434	9	879
435	9	688
436	9	880
437	9	883
438	9	889
439	9	892
440	9	894
441	9	895
442	9	903
443	9	908
444	9	910
445	9	913
446	9	920
447	9	921
448	9	922
449	9	523
450	9	520
451	9	923
452	9	924
453	9	925
454	9	926
455	9	609
456	9	927
457	9	928
458	9	612
459	9	613
460	9	931
461	9	610
462	9	611
463	9	933
464	9	934
465	9	624
466	9	627
467	9	628
468	9	625
469	9	626
470	9	936
471	9	937
472	9	938
473	9	939
474	9	940
475	9	941
476	9	942
477	9	943
478	9	944
479	9	945
480	9	946
481	9	694
482	9	697
483	9	950
484	9	947
485	9	948
486	9	952
487	9	949
488	9	953
489	9	951
490	9	698
491	9	954
492	9	695
493	9	955
494	9	956
495	9	957
496	9	958
497	9	959
498	9	696
499	9	960
500	9	961
501	9	935
502	9	743
503	9	704
504	9	707
505	9	708
506	9	705
507	9	706
508	9	499
509	9	502
510	9	503
511	9	500
512	9	501
513	9	975
514	9	639
515	9	642
516	9	976
517	9	643
518	9	640
519	9	977
520	9	978
521	9	979
522	9	980
523	9	641
524	9	981
525	9	644
526	9	647
527	9	982
528	9	648
529	9	645
530	9	646
531	9	963
532	9	964
533	9	965
534	9	652
535	9	966
536	9	967
537	9	968
538	9	969
539	9	970
540	9	971
541	9	972
542	9	973
543	9	974
544	9	651
545	9	490
546	9	493
547	9	986
548	9	987
549	9	990
550	9	991
551	9	992
552	9	993
553	9	749
554	9	752
555	9	996
556	9	753
557	9	994
558	9	995
559	9	750
560	9	751
561	9	997
562	9	1000
563	9	1001
564	9	789
565	9	792
566	9	793
567	9	1003
568	9	790
569	9	1002
570	9	791
571	10	834
572	10	798
573	10	837
574	10	795
575	10	800
576	10	840
577	10	465
578	10	468
579	10	842
580	10	843
581	10	846
582	10	848
583	10	850
584	10	852
585	10	853
586	10	568
587	10	854
588	10	565
589	10	851
590	10	861
591	10	570
592	10	867
593	10	578
594	10	868
595	10	575
596	10	585
597	10	874
598	10	878
599	10	879
600	10	876
601	10	688
602	10	880
603	10	889
604	10	892
605	10	894
606	10	903
607	10	908
608	10	913
609	10	920
610	10	922
611	10	523
612	10	520
613	10	613
614	10	931
615	10	610
616	10	934
617	10	936
618	10	937
619	10	940
620	10	941
621	10	943
622	10	944
623	10	948
624	10	952
625	10	953
626	10	698
627	10	954
628	10	947
629	10	955
630	10	956
631	10	957
632	10	958
633	10	959
634	10	743
635	10	978
636	10	979
637	10	981
638	10	645
639	10	965
640	10	966
641	10	967
642	10	968
643	10	969
644	10	970
645	10	972
646	10	973
647	10	974
649	10	490
650	10	493
651	10	986
652	10	997
653	10	1000
654	10	1001
655	10	793
656	10	1003
657	10	1002
658	11	844
659	11	853
660	11	861
661	11	867
662	11	874
663	11	975
664	11	688
665	11	991
666	11	992
667	11	993
668	11	753
669	11	994
670	11	995
671	11	1000
672	11	880
673	11	894
674	11	903
675	11	908
676	11	913
677	11	986
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add permission	1	add_permission
2	Can change permission	1	change_permission
3	Can delete permission	1	delete_permission
4	Can view permission	1	view_permission
5	Can add group	2	add_group
6	Can change group	2	change_group
7	Can delete group	2	delete_group
8	Can view group	2	view_group
9	Can add user	3	add_user
10	Can change user	3	change_user
11	Can delete user	3	delete_user
12	Can view user	3	view_user
13	Can add content type	4	add_contenttype
14	Can change content type	4	change_contenttype
15	Can delete content type	4	delete_contenttype
16	Can view content type	4	view_contenttype
17	Can add session	5	add_session
18	Can change session	5	change_session
19	Can delete session	5	delete_session
20	Can view session	5	view_session
21	Can add site	6	add_site
22	Can change site	6	change_site
23	Can delete site	6	delete_site
24	Can view site	6	view_site
25	Can add Token	7	add_token
26	Can change Token	7	change_token
27	Can delete Token	7	delete_token
28	Can view Token	7	view_token
29	Can add token	8	add_tokenproxy
30	Can change token	8	change_tokenproxy
31	Can delete token	8	delete_tokenproxy
32	Can view token	8	view_tokenproxy
33	Can add import task	9	add_importtask
34	Can change import task	9	change_importtask
35	Can delete import task	9	delete_importtask
36	Can view import task	9	view_importtask
37	Can add failed login	10	add_failedlogin
38	Can change failed login	10	change_failedlogin
39	Can delete failed login	10	delete_failedlogin
40	Can view failed login	10	view_failedlogin
41	Can add password history	11	add_passwordhistory
42	Can change password history	11	change_passwordhistory
43	Can delete password history	11	delete_passwordhistory
44	Can view password history	11	view_passwordhistory
45	Can add recovery token	12	add_recoverytoken
46	Can change recovery token	12	change_recoverytoken
47	Can delete recovery token	12	delete_recoverytoken
48	Can view recovery token	12	view_recoverytoken
49	Can add apk	13	add_apk
50	Can change apk	13	change_apk
51	Can delete apk	13	delete_apk
52	Can view apk	13	view_apk
53	Can add archive	14	add_archive
54	Can change archive	14	change_archive
55	Can delete archive	14	delete_archive
56	Can view archive	14	view_archive
57	Can add api token	15	add_apitoken
58	Can change api token	15	change_apitoken
59	Can delete api token	15	delete_apitoken
60	Can view api token	15	view_apitoken
61	Can add resthook	16	add_resthook
62	Can change resthook	16	change_resthook
63	Can delete resthook	16	delete_resthook
64	Can view resthook	16	view_resthook
65	Can add resthook subscriber	17	add_resthooksubscriber
66	Can change resthook subscriber	17	change_resthooksubscriber
67	Can delete resthook subscriber	17	delete_resthooksubscriber
68	Can view resthook subscriber	17	view_resthooksubscriber
69	Can add web hook event	18	add_webhookevent
70	Can change web hook event	18	change_webhookevent
71	Can delete web hook event	18	delete_webhookevent
72	Can view web hook event	18	view_webhookevent
73	Can add http log	19	add_httplog
74	Can change http log	19	change_httplog
75	Can delete http log	19	delete_httplog
76	Can view http log	19	view_httplog
77	Can add classifier	20	add_classifier
78	Can change classifier	20	change_classifier
79	Can delete classifier	20	delete_classifier
80	Can view classifier	20	view_classifier
81	Can add intent	21	add_intent
82	Can change intent	21	change_intent
83	Can delete intent	21	delete_intent
84	Can view intent	21	view_intent
85	Can add global	22	add_global
86	Can change global	22	change_global
87	Can delete global	22	delete_global
88	Can view global	22	view_global
89	Can add video	23	add_video
90	Can change video	23	change_video
91	Can delete video	23	delete_video
92	Can view video	23	view_video
93	Can add lead	24	add_lead
94	Can change lead	24	change_lead
95	Can delete lead	24	delete_lead
96	Can view lead	24	view_lead
97	Can add policy	25	add_policy
98	Can change policy	25	change_policy
99	Can delete policy	25	delete_policy
100	Can view policy	25	view_policy
101	Can add consent	26	add_consent
102	Can change consent	26	change_consent
103	Can delete consent	26	delete_consent
104	Can view consent	26	view_consent
105	Can add schedule	27	add_schedule
106	Can change schedule	27	change_schedule
107	Can delete schedule	27	delete_schedule
108	Can view schedule	27	view_schedule
109	Can add template	28	add_template
110	Can change template	28	change_template
111	Can delete template	28	delete_template
112	Can view template	28	view_template
113	Can add template translation	29	add_templatetranslation
114	Can change template translation	29	change_templatetranslation
115	Can delete template translation	29	delete_templatetranslation
116	Can view template translation	29	view_templatetranslation
117	Can add org	30	add_org
118	Can change org	30	change_org
119	Can delete org	30	delete_org
120	Can view org	30	view_org
121	Can add top up	31	add_topup
122	Can change top up	31	change_topup
123	Can delete top up	31	delete_topup
124	Can view top up	31	view_topup
125	Can add user settings	32	add_usersettings
126	Can change user settings	32	change_usersettings
127	Can delete user settings	32	delete_usersettings
128	Can view user settings	32	view_usersettings
129	Can add top up credits	33	add_topupcredits
130	Can change top up credits	33	change_topupcredits
131	Can delete top up credits	33	delete_topupcredits
132	Can view top up credits	33	view_topupcredits
133	Can add invitation	34	add_invitation
134	Can change invitation	34	change_invitation
135	Can delete invitation	34	delete_invitation
136	Can view invitation	34	view_invitation
137	Can add debit	35	add_debit
138	Can change debit	35	change_debit
139	Can delete debit	35	delete_debit
140	Can view debit	35	view_debit
141	Can add credit alert	36	add_creditalert
142	Can change credit alert	36	change_creditalert
143	Can delete credit alert	36	delete_creditalert
144	Can view credit alert	36	view_creditalert
145	Can add backup token	37	add_backuptoken
146	Can change backup token	37	change_backuptoken
147	Can delete backup token	37	delete_backuptoken
148	Can view backup token	37	view_backuptoken
149	Can add org activity	38	add_orgactivity
150	Can change org activity	38	change_orgactivity
151	Can delete org activity	38	delete_orgactivity
152	Can view org activity	38	view_orgactivity
153	Can add user	39	add_user
154	Can change user	39	change_user
155	Can delete user	39	delete_user
156	Can view user	39	view_user
157	Can add contact	40	add_contact
158	Can change contact	40	change_contact
159	Can delete contact	40	delete_contact
160	Can view contact	40	view_contact
161	Can add contact field	41	add_contactfield
162	Can change contact field	41	change_contactfield
163	Can delete contact field	41	delete_contactfield
164	Can view contact field	41	view_contactfield
165	Can add Group	42	add_contactgroup
166	Can change Group	42	change_contactgroup
167	Can delete Group	42	delete_contactgroup
168	Can view Group	42	view_contactgroup
169	Can add contact group count	43	add_contactgroupcount
170	Can change contact group count	43	change_contactgroupcount
171	Can delete contact group count	43	delete_contactgroupcount
172	Can view contact group count	43	view_contactgroupcount
173	Can add contact import	44	add_contactimport
174	Can change contact import	44	change_contactimport
175	Can delete contact import	44	delete_contactimport
176	Can view contact import	44	view_contactimport
177	Can add contact import batch	45	add_contactimportbatch
178	Can change contact import batch	45	change_contactimportbatch
179	Can delete contact import batch	45	delete_contactimportbatch
180	Can view contact import batch	45	view_contactimportbatch
181	Can add contact urn	46	add_contacturn
182	Can change contact urn	46	change_contacturn
183	Can delete contact urn	46	delete_contacturn
184	Can view contact urn	46	view_contacturn
185	Can add export contacts task	47	add_exportcontactstask
186	Can change export contacts task	47	change_exportcontactstask
187	Can delete export contacts task	47	delete_exportcontactstask
188	Can view export contacts task	47	view_exportcontactstask
189	Can add alert	48	add_alert
190	Can change alert	48	change_alert
191	Can delete alert	48	delete_alert
192	Can view alert	48	view_alert
193	Can add channel	49	add_channel
194	Can change channel	49	change_channel
195	Can delete channel	49	delete_channel
196	Can view channel	49	view_channel
197	Can add channel connection	50	add_channelconnection
198	Can change channel connection	50	change_channelconnection
199	Can delete channel connection	50	delete_channelconnection
200	Can view channel connection	50	view_channelconnection
201	Can add channel count	51	add_channelcount
202	Can change channel count	51	change_channelcount
203	Can delete channel count	51	delete_channelcount
204	Can view channel count	51	view_channelcount
205	Can add channel event	52	add_channelevent
206	Can change channel event	52	change_channelevent
207	Can delete channel event	52	delete_channelevent
208	Can view channel event	52	view_channelevent
209	Can add sync event	53	add_syncevent
210	Can change sync event	53	change_syncevent
211	Can delete sync event	53	delete_syncevent
212	Can view sync event	53	view_syncevent
213	Can add channel log	54	add_channellog
214	Can change channel log	54	change_channellog
215	Can delete channel log	54	delete_channellog
216	Can view channel log	54	view_channellog
217	Can add broadcast	55	add_broadcast
218	Can change broadcast	55	change_broadcast
219	Can delete broadcast	55	delete_broadcast
220	Can view broadcast	55	view_broadcast
221	Can add label	56	add_label
222	Can change label	56	change_label
223	Can delete label	56	delete_label
224	Can view label	56	view_label
225	Can add msg	57	add_msg
226	Can change msg	57	change_msg
227	Can delete msg	57	delete_msg
228	Can view msg	57	view_msg
229	Can add label count	58	add_labelcount
230	Can change label count	58	change_labelcount
231	Can delete label count	58	delete_labelcount
232	Can view label count	58	view_labelcount
233	Can add export messages task	59	add_exportmessagestask
234	Can change export messages task	59	change_exportmessagestask
235	Can delete export messages task	59	delete_exportmessagestask
236	Can view export messages task	59	view_exportmessagestask
237	Can add broadcast msg count	60	add_broadcastmsgcount
238	Can change broadcast msg count	60	change_broadcastmsgcount
239	Can delete broadcast msg count	60	delete_broadcastmsgcount
240	Can view broadcast msg count	60	view_broadcastmsgcount
241	Can add system label count	61	add_systemlabelcount
242	Can change system label count	61	change_systemlabelcount
243	Can delete system label count	61	delete_systemlabelcount
244	Can view system label count	61	view_systemlabelcount
245	Can add incident	62	add_incident
246	Can change incident	62	change_incident
247	Can delete incident	62	delete_incident
248	Can view incident	62	view_incident
249	Can add notification count	63	add_notificationcount
250	Can change notification count	63	change_notificationcount
251	Can delete notification count	63	delete_notificationcount
252	Can view notification count	63	view_notificationcount
253	Can add notification	64	add_notification
254	Can change notification	64	change_notification
255	Can delete notification	64	delete_notification
256	Can view notification	64	view_notification
257	Can add export flow results task	65	add_exportflowresultstask
258	Can change export flow results task	65	change_exportflowresultstask
259	Can delete export flow results task	65	delete_exportflowresultstask
260	Can view export flow results task	65	view_exportflowresultstask
261	Can add Flow	66	add_flow
262	Can change Flow	66	change_flow
263	Can delete Flow	66	delete_flow
264	Can view Flow	66	view_flow
265	Can add flow category count	67	add_flowcategorycount
266	Can change flow category count	67	change_flowcategorycount
267	Can delete flow category count	67	delete_flowcategorycount
268	Can view flow category count	67	view_flowcategorycount
269	Can add flow label	68	add_flowlabel
270	Can change flow label	68	change_flowlabel
271	Can delete flow label	68	delete_flowlabel
272	Can view flow label	68	view_flowlabel
273	Can add flow node count	69	add_flownodecount
274	Can change flow node count	69	change_flownodecount
275	Can delete flow node count	69	delete_flownodecount
276	Can view flow node count	69	view_flownodecount
277	Can add flow path count	70	add_flowpathcount
278	Can change flow path count	70	change_flowpathcount
279	Can delete flow path count	70	delete_flowpathcount
280	Can view flow path count	70	view_flowpathcount
281	Can add flow revision	71	add_flowrevision
282	Can change flow revision	71	change_flowrevision
283	Can delete flow revision	71	delete_flowrevision
284	Can view flow revision	71	view_flowrevision
285	Can add flow run	72	add_flowrun
286	Can change flow run	72	change_flowrun
287	Can delete flow run	72	delete_flowrun
288	Can view flow run	72	view_flowrun
289	Can add flow run count	73	add_flowruncount
290	Can change flow run count	73	change_flowruncount
291	Can delete flow run count	73	delete_flowruncount
292	Can view flow run count	73	view_flowruncount
293	Can add flow session	74	add_flowsession
294	Can change flow session	74	change_flowsession
295	Can delete flow session	74	delete_flowsession
296	Can view flow session	74	view_flowsession
297	Can add flow start	75	add_flowstart
298	Can change flow start	75	change_flowstart
299	Can delete flow start	75	delete_flowstart
300	Can view flow start	75	view_flowstart
301	Can add flow start count	76	add_flowstartcount
302	Can change flow start count	76	change_flowstartcount
303	Can delete flow start count	76	delete_flowstartcount
304	Can view flow start count	76	view_flowstartcount
305	Can add ticket	77	add_ticket
306	Can change ticket	77	change_ticket
307	Can delete ticket	77	delete_ticket
308	Can view ticket	77	view_ticket
309	Can add topic	78	add_topic
310	Can change topic	78	change_topic
311	Can delete topic	78	delete_topic
312	Can view topic	78	view_topic
313	Can add ticket event	79	add_ticketevent
314	Can change ticket event	79	change_ticketevent
315	Can delete ticket event	79	delete_ticketevent
316	Can view ticket event	79	view_ticketevent
317	Can add ticketer	80	add_ticketer
318	Can change ticketer	80	change_ticketer
319	Can delete ticketer	80	delete_ticketer
320	Can view ticketer	80	view_ticketer
321	Can add ticket count	81	add_ticketcount
322	Can change ticket count	81	change_ticketcount
323	Can delete ticket count	81	delete_ticketcount
324	Can view ticket count	81	view_ticketcount
325	Can add team	82	add_team
326	Can change team	82	change_team
327	Can delete team	82	delete_team
328	Can view team	82	view_team
329	Can add ticket daily count	83	add_ticketdailycount
330	Can change ticket daily count	83	change_ticketdailycount
331	Can delete ticket daily count	83	delete_ticketdailycount
332	Can view ticket daily count	83	view_ticketdailycount
333	Can add ticket daily timing	84	add_ticketdailytiming
334	Can change ticket daily timing	84	change_ticketdailytiming
335	Can delete ticket daily timing	84	delete_ticketdailytiming
336	Can view ticket daily timing	84	view_ticketdailytiming
337	Can add Trigger	85	add_trigger
338	Can change Trigger	85	change_trigger
339	Can delete Trigger	85	delete_trigger
340	Can view Trigger	85	view_trigger
341	Can add Campaign	86	add_campaign
342	Can change Campaign	86	change_campaign
343	Can delete Campaign	86	delete_campaign
344	Can view Campaign	86	view_campaign
345	Can add Campaign Event	87	add_campaignevent
346	Can change Campaign Event	87	change_campaignevent
347	Can delete Campaign Event	87	delete_campaignevent
348	Can view Campaign Event	87	view_campaignevent
349	Can add event fire	88	add_eventfire
350	Can change event fire	88	change_eventfire
351	Can delete event fire	88	delete_eventfire
352	Can view event fire	88	view_eventfire
353	Can add ivr call	89	add_ivrcall
354	Can change ivr call	89	change_ivrcall
355	Can delete ivr call	89	delete_ivrcall
356	Can view ivr call	89	view_ivrcall
357	Can add admin boundary	90	add_adminboundary
358	Can change admin boundary	90	change_adminboundary
359	Can delete admin boundary	90	delete_adminboundary
360	Can view admin boundary	90	view_adminboundary
361	Can add boundary alias	91	add_boundaryalias
362	Can change boundary alias	91	change_boundaryalias
363	Can delete boundary alias	91	delete_boundaryalias
364	Can view boundary alias	91	view_boundaryalias
365	Can add airtime transfer	92	add_airtimetransfer
366	Can change airtime transfer	92	change_airtimetransfer
367	Can delete airtime transfer	92	delete_airtimetransfer
368	Can view airtime transfer	92	view_airtimetransfer
369	Can create permission	1	permission_create
370	Can read permission	1	permission_read
371	Can update permission	1	permission_update
372	Can delete permission	1	permission_delete
373	Can list permission	1	permission_list
374	Can create group	2	group_create
375	Can read group	2	group_read
376	Can update group	2	group_update
377	Can delete group	2	group_delete
378	Can list group	2	group_list
379	Can create user	3	user_create
380	Can read user	3	user_read
381	Can update user	3	user_update
382	Can delete user	3	user_delete
383	Can list user	3	user_list
384	Can create content type	4	contenttype_create
385	Can read content type	4	contenttype_read
386	Can update content type	4	contenttype_update
387	Can delete content type	4	contenttype_delete
388	Can list content type	4	contenttype_list
389	Can create session	5	session_create
390	Can read session	5	session_read
391	Can update session	5	session_update
392	Can delete session	5	session_delete
393	Can list session	5	session_list
394	Can create site	6	site_create
395	Can read site	6	site_read
396	Can update site	6	site_update
397	Can delete site	6	site_delete
398	Can list site	6	site_list
399	Can create Token	7	token_create
400	Can read Token	7	token_read
401	Can update Token	7	token_update
402	Can delete Token	7	token_delete
403	Can list Token	7	token_list
404	Can create token	8	tokenproxy_create
405	Can read token	8	tokenproxy_read
406	Can update token	8	tokenproxy_update
407	Can delete token	8	tokenproxy_delete
408	Can list token	8	tokenproxy_list
409	Can create import task	9	importtask_create
410	Can read import task	9	importtask_read
411	Can update import task	9	importtask_update
412	Can delete import task	9	importtask_delete
413	Can list import task	9	importtask_list
414	Can create failed login	10	failedlogin_create
415	Can read failed login	10	failedlogin_read
416	Can update failed login	10	failedlogin_update
417	Can delete failed login	10	failedlogin_delete
418	Can list failed login	10	failedlogin_list
419	Can create password history	11	passwordhistory_create
420	Can read password history	11	passwordhistory_read
421	Can update password history	11	passwordhistory_update
422	Can delete password history	11	passwordhistory_delete
423	Can list password history	11	passwordhistory_list
424	Can create recovery token	12	recoverytoken_create
425	Can read recovery token	12	recoverytoken_read
426	Can update recovery token	12	recoverytoken_update
427	Can delete recovery token	12	recoverytoken_delete
428	Can list recovery token	12	recoverytoken_list
429	Can create apk	13	apk_create
430	Can read apk	13	apk_read
431	Can update apk	13	apk_update
432	Can delete apk	13	apk_delete
433	Can list apk	13	apk_list
434	Can create archive	14	archive_create
435	Can read archive	14	archive_read
436	Can update archive	14	archive_update
437	Can delete archive	14	archive_delete
438	Can list archive	14	archive_list
439	Can create api token	15	apitoken_create
440	Can read api token	15	apitoken_read
441	Can update api token	15	apitoken_update
442	Can delete api token	15	apitoken_delete
443	Can list api token	15	apitoken_list
444	Can create resthook	16	resthook_create
445	Can read resthook	16	resthook_read
446	Can update resthook	16	resthook_update
447	Can delete resthook	16	resthook_delete
448	Can list resthook	16	resthook_list
449	Can create resthook subscriber	17	resthooksubscriber_create
450	Can read resthook subscriber	17	resthooksubscriber_read
451	Can update resthook subscriber	17	resthooksubscriber_update
452	Can delete resthook subscriber	17	resthooksubscriber_delete
453	Can list resthook subscriber	17	resthooksubscriber_list
454	Can create web hook event	18	webhookevent_create
455	Can read web hook event	18	webhookevent_read
456	Can update web hook event	18	webhookevent_update
457	Can delete web hook event	18	webhookevent_delete
458	Can list web hook event	18	webhookevent_list
459	Can create http log	19	httplog_create
460	Can read http log	19	httplog_read
461	Can update http log	19	httplog_update
462	Can delete http log	19	httplog_delete
463	Can list http log	19	httplog_list
464	Can create classifier	20	classifier_create
465	Can read classifier	20	classifier_read
466	Can update classifier	20	classifier_update
467	Can delete classifier	20	classifier_delete
468	Can list classifier	20	classifier_list
469	Can create intent	21	intent_create
470	Can read intent	21	intent_read
471	Can update intent	21	intent_update
472	Can delete intent	21	intent_delete
473	Can list intent	21	intent_list
474	Can create global	22	global_create
475	Can read global	22	global_read
476	Can update global	22	global_update
477	Can delete global	22	global_delete
478	Can list global	22	global_list
479	Can create video	23	video_create
480	Can read video	23	video_read
481	Can update video	23	video_update
482	Can delete video	23	video_delete
483	Can list video	23	video_list
484	Can create lead	24	lead_create
485	Can read lead	24	lead_read
486	Can update lead	24	lead_update
487	Can delete lead	24	lead_delete
488	Can list lead	24	lead_list
489	Can create policy	25	policy_create
490	Can read policy	25	policy_read
491	Can update policy	25	policy_update
492	Can delete policy	25	policy_delete
493	Can list policy	25	policy_list
494	Can create consent	26	consent_create
495	Can read consent	26	consent_read
496	Can update consent	26	consent_update
497	Can delete consent	26	consent_delete
498	Can list consent	26	consent_list
499	Can create schedule	27	schedule_create
500	Can read schedule	27	schedule_read
501	Can update schedule	27	schedule_update
502	Can delete schedule	27	schedule_delete
503	Can list schedule	27	schedule_list
504	Can create template	28	template_create
505	Can read template	28	template_read
506	Can update template	28	template_update
507	Can delete template	28	template_delete
508	Can list template	28	template_list
509	Can create template translation	29	templatetranslation_create
510	Can read template translation	29	templatetranslation_read
511	Can update template translation	29	templatetranslation_update
512	Can delete template translation	29	templatetranslation_delete
513	Can list template translation	29	templatetranslation_list
514	Can create org	30	org_create
515	Can read org	30	org_read
516	Can update org	30	org_update
517	Can delete org	30	org_delete
518	Can list org	30	org_list
519	Can create top up	31	topup_create
520	Can read top up	31	topup_read
521	Can update top up	31	topup_update
522	Can delete top up	31	topup_delete
523	Can list top up	31	topup_list
524	Can create user settings	32	usersettings_create
525	Can read user settings	32	usersettings_read
526	Can update user settings	32	usersettings_update
527	Can delete user settings	32	usersettings_delete
528	Can list user settings	32	usersettings_list
529	Can create top up credits	33	topupcredits_create
530	Can read top up credits	33	topupcredits_read
531	Can update top up credits	33	topupcredits_update
532	Can delete top up credits	33	topupcredits_delete
533	Can list top up credits	33	topupcredits_list
534	Can create invitation	34	invitation_create
535	Can read invitation	34	invitation_read
536	Can update invitation	34	invitation_update
537	Can delete invitation	34	invitation_delete
538	Can list invitation	34	invitation_list
539	Can create debit	35	debit_create
540	Can read debit	35	debit_read
541	Can update debit	35	debit_update
542	Can delete debit	35	debit_delete
543	Can list debit	35	debit_list
544	Can create credit alert	36	creditalert_create
545	Can read credit alert	36	creditalert_read
546	Can update credit alert	36	creditalert_update
547	Can delete credit alert	36	creditalert_delete
548	Can list credit alert	36	creditalert_list
549	Can create backup token	37	backuptoken_create
550	Can read backup token	37	backuptoken_read
551	Can update backup token	37	backuptoken_update
552	Can delete backup token	37	backuptoken_delete
553	Can list backup token	37	backuptoken_list
554	Can create org activity	38	orgactivity_create
555	Can read org activity	38	orgactivity_read
556	Can update org activity	38	orgactivity_update
557	Can delete org activity	38	orgactivity_delete
558	Can list org activity	38	orgactivity_list
559	Can create user	39	user_create
560	Can read user	39	user_read
561	Can update user	39	user_update
562	Can delete user	39	user_delete
563	Can list user	39	user_list
564	Can create contact	40	contact_create
565	Can read contact	40	contact_read
566	Can update contact	40	contact_update
567	Can delete contact	40	contact_delete
568	Can list contact	40	contact_list
569	Can create contact field	41	contactfield_create
570	Can read contact field	41	contactfield_read
571	Can update contact field	41	contactfield_update
572	Can delete contact field	41	contactfield_delete
573	Can list contact field	41	contactfield_list
574	Can create Group	42	contactgroup_create
575	Can read Group	42	contactgroup_read
576	Can update Group	42	contactgroup_update
577	Can delete Group	42	contactgroup_delete
578	Can list Group	42	contactgroup_list
579	Can create contact group count	43	contactgroupcount_create
580	Can read contact group count	43	contactgroupcount_read
581	Can update contact group count	43	contactgroupcount_update
582	Can delete contact group count	43	contactgroupcount_delete
583	Can list contact group count	43	contactgroupcount_list
584	Can create contact import	44	contactimport_create
585	Can read contact import	44	contactimport_read
586	Can update contact import	44	contactimport_update
587	Can delete contact import	44	contactimport_delete
588	Can list contact import	44	contactimport_list
589	Can create contact import batch	45	contactimportbatch_create
590	Can read contact import batch	45	contactimportbatch_read
591	Can update contact import batch	45	contactimportbatch_update
592	Can delete contact import batch	45	contactimportbatch_delete
593	Can list contact import batch	45	contactimportbatch_list
594	Can create contact urn	46	contacturn_create
595	Can read contact urn	46	contacturn_read
596	Can update contact urn	46	contacturn_update
597	Can delete contact urn	46	contacturn_delete
598	Can list contact urn	46	contacturn_list
599	Can create export contacts task	47	exportcontactstask_create
600	Can read export contacts task	47	exportcontactstask_read
601	Can update export contacts task	47	exportcontactstask_update
602	Can delete export contacts task	47	exportcontactstask_delete
603	Can list export contacts task	47	exportcontactstask_list
604	Can create alert	48	alert_create
605	Can read alert	48	alert_read
606	Can update alert	48	alert_update
607	Can delete alert	48	alert_delete
608	Can list alert	48	alert_list
609	Can create channel	49	channel_create
610	Can read channel	49	channel_read
611	Can update channel	49	channel_update
612	Can delete channel	49	channel_delete
613	Can list channel	49	channel_list
614	Can create channel connection	50	channelconnection_create
615	Can read channel connection	50	channelconnection_read
616	Can update channel connection	50	channelconnection_update
617	Can delete channel connection	50	channelconnection_delete
618	Can list channel connection	50	channelconnection_list
619	Can create channel count	51	channelcount_create
620	Can read channel count	51	channelcount_read
621	Can update channel count	51	channelcount_update
622	Can delete channel count	51	channelcount_delete
623	Can list channel count	51	channelcount_list
624	Can create channel event	52	channelevent_create
625	Can read channel event	52	channelevent_read
626	Can update channel event	52	channelevent_update
627	Can delete channel event	52	channelevent_delete
628	Can list channel event	52	channelevent_list
629	Can create sync event	53	syncevent_create
630	Can read sync event	53	syncevent_read
631	Can update sync event	53	syncevent_update
632	Can delete sync event	53	syncevent_delete
633	Can list sync event	53	syncevent_list
634	Can create channel log	54	channellog_create
635	Can read channel log	54	channellog_read
636	Can update channel log	54	channellog_update
637	Can delete channel log	54	channellog_delete
638	Can list channel log	54	channellog_list
639	Can create broadcast	55	broadcast_create
640	Can read broadcast	55	broadcast_read
641	Can update broadcast	55	broadcast_update
642	Can delete broadcast	55	broadcast_delete
643	Can list broadcast	55	broadcast_list
644	Can create label	56	label_create
645	Can read label	56	label_read
646	Can update label	56	label_update
647	Can delete label	56	label_delete
648	Can list label	56	label_list
649	Can create msg	57	msg_create
650	Can read msg	57	msg_read
651	Can update msg	57	msg_update
652	Can delete msg	57	msg_delete
653	Can list msg	57	msg_list
654	Can create label count	58	labelcount_create
655	Can read label count	58	labelcount_read
656	Can update label count	58	labelcount_update
657	Can delete label count	58	labelcount_delete
658	Can list label count	58	labelcount_list
659	Can create export messages task	59	exportmessagestask_create
660	Can read export messages task	59	exportmessagestask_read
661	Can update export messages task	59	exportmessagestask_update
662	Can delete export messages task	59	exportmessagestask_delete
663	Can list export messages task	59	exportmessagestask_list
664	Can create broadcast msg count	60	broadcastmsgcount_create
665	Can read broadcast msg count	60	broadcastmsgcount_read
666	Can update broadcast msg count	60	broadcastmsgcount_update
667	Can delete broadcast msg count	60	broadcastmsgcount_delete
668	Can list broadcast msg count	60	broadcastmsgcount_list
669	Can create system label count	61	systemlabelcount_create
670	Can read system label count	61	systemlabelcount_read
671	Can update system label count	61	systemlabelcount_update
672	Can delete system label count	61	systemlabelcount_delete
673	Can list system label count	61	systemlabelcount_list
674	Can create incident	62	incident_create
675	Can read incident	62	incident_read
676	Can update incident	62	incident_update
677	Can delete incident	62	incident_delete
678	Can list incident	62	incident_list
679	Can create notification count	63	notificationcount_create
680	Can read notification count	63	notificationcount_read
681	Can update notification count	63	notificationcount_update
682	Can delete notification count	63	notificationcount_delete
683	Can list notification count	63	notificationcount_list
684	Can create notification	64	notification_create
685	Can read notification	64	notification_read
686	Can update notification	64	notification_update
687	Can delete notification	64	notification_delete
688	Can list notification	64	notification_list
689	Can create export flow results task	65	exportflowresultstask_create
690	Can read export flow results task	65	exportflowresultstask_read
691	Can update export flow results task	65	exportflowresultstask_update
692	Can delete export flow results task	65	exportflowresultstask_delete
693	Can list export flow results task	65	exportflowresultstask_list
694	Can create Flow	66	flow_create
695	Can read Flow	66	flow_read
696	Can update Flow	66	flow_update
697	Can delete Flow	66	flow_delete
698	Can list Flow	66	flow_list
699	Can create flow category count	67	flowcategorycount_create
700	Can read flow category count	67	flowcategorycount_read
701	Can update flow category count	67	flowcategorycount_update
702	Can delete flow category count	67	flowcategorycount_delete
703	Can list flow category count	67	flowcategorycount_list
704	Can create flow label	68	flowlabel_create
705	Can read flow label	68	flowlabel_read
706	Can update flow label	68	flowlabel_update
707	Can delete flow label	68	flowlabel_delete
708	Can list flow label	68	flowlabel_list
709	Can create flow node count	69	flownodecount_create
710	Can read flow node count	69	flownodecount_read
711	Can update flow node count	69	flownodecount_update
712	Can delete flow node count	69	flownodecount_delete
713	Can list flow node count	69	flownodecount_list
714	Can create flow path count	70	flowpathcount_create
715	Can read flow path count	70	flowpathcount_read
716	Can update flow path count	70	flowpathcount_update
717	Can delete flow path count	70	flowpathcount_delete
718	Can list flow path count	70	flowpathcount_list
719	Can create flow revision	71	flowrevision_create
720	Can read flow revision	71	flowrevision_read
721	Can update flow revision	71	flowrevision_update
722	Can delete flow revision	71	flowrevision_delete
723	Can list flow revision	71	flowrevision_list
724	Can create flow run	72	flowrun_create
725	Can read flow run	72	flowrun_read
726	Can update flow run	72	flowrun_update
727	Can delete flow run	72	flowrun_delete
728	Can list flow run	72	flowrun_list
729	Can create flow run count	73	flowruncount_create
730	Can read flow run count	73	flowruncount_read
731	Can update flow run count	73	flowruncount_update
732	Can delete flow run count	73	flowruncount_delete
733	Can list flow run count	73	flowruncount_list
734	Can create flow session	74	flowsession_create
735	Can read flow session	74	flowsession_read
736	Can update flow session	74	flowsession_update
737	Can delete flow session	74	flowsession_delete
738	Can list flow session	74	flowsession_list
739	Can create flow start	75	flowstart_create
740	Can read flow start	75	flowstart_read
741	Can update flow start	75	flowstart_update
742	Can delete flow start	75	flowstart_delete
743	Can list flow start	75	flowstart_list
744	Can create flow start count	76	flowstartcount_create
745	Can read flow start count	76	flowstartcount_read
746	Can update flow start count	76	flowstartcount_update
747	Can delete flow start count	76	flowstartcount_delete
748	Can list flow start count	76	flowstartcount_list
749	Can create ticket	77	ticket_create
750	Can read ticket	77	ticket_read
751	Can update ticket	77	ticket_update
752	Can delete ticket	77	ticket_delete
753	Can list ticket	77	ticket_list
754	Can create topic	78	topic_create
755	Can read topic	78	topic_read
756	Can update topic	78	topic_update
757	Can delete topic	78	topic_delete
758	Can list topic	78	topic_list
759	Can create ticket event	79	ticketevent_create
760	Can read ticket event	79	ticketevent_read
761	Can update ticket event	79	ticketevent_update
762	Can delete ticket event	79	ticketevent_delete
763	Can list ticket event	79	ticketevent_list
764	Can create ticketer	80	ticketer_create
765	Can read ticketer	80	ticketer_read
766	Can update ticketer	80	ticketer_update
767	Can delete ticketer	80	ticketer_delete
768	Can list ticketer	80	ticketer_list
769	Can create ticket count	81	ticketcount_create
770	Can read ticket count	81	ticketcount_read
771	Can update ticket count	81	ticketcount_update
772	Can delete ticket count	81	ticketcount_delete
773	Can list ticket count	81	ticketcount_list
774	Can create team	82	team_create
775	Can read team	82	team_read
776	Can update team	82	team_update
777	Can delete team	82	team_delete
778	Can list team	82	team_list
779	Can create ticket daily count	83	ticketdailycount_create
780	Can read ticket daily count	83	ticketdailycount_read
781	Can update ticket daily count	83	ticketdailycount_update
782	Can delete ticket daily count	83	ticketdailycount_delete
783	Can list ticket daily count	83	ticketdailycount_list
784	Can create ticket daily timing	84	ticketdailytiming_create
785	Can read ticket daily timing	84	ticketdailytiming_read
786	Can update ticket daily timing	84	ticketdailytiming_update
787	Can delete ticket daily timing	84	ticketdailytiming_delete
788	Can list ticket daily timing	84	ticketdailytiming_list
789	Can create Trigger	85	trigger_create
790	Can read Trigger	85	trigger_read
791	Can update Trigger	85	trigger_update
792	Can delete Trigger	85	trigger_delete
793	Can list Trigger	85	trigger_list
794	Can create Campaign	86	campaign_create
795	Can read Campaign	86	campaign_read
796	Can update Campaign	86	campaign_update
797	Can delete Campaign	86	campaign_delete
798	Can list Campaign	86	campaign_list
799	Can create Campaign Event	87	campaignevent_create
800	Can read Campaign Event	87	campaignevent_read
801	Can update Campaign Event	87	campaignevent_update
802	Can delete Campaign Event	87	campaignevent_delete
803	Can list Campaign Event	87	campaignevent_list
804	Can create event fire	88	eventfire_create
805	Can read event fire	88	eventfire_read
806	Can update event fire	88	eventfire_update
807	Can delete event fire	88	eventfire_delete
808	Can list event fire	88	eventfire_list
809	Can create ivr call	89	ivrcall_create
810	Can read ivr call	89	ivrcall_read
811	Can update ivr call	89	ivrcall_update
812	Can delete ivr call	89	ivrcall_delete
813	Can list ivr call	89	ivrcall_list
814	Can create admin boundary	90	adminboundary_create
815	Can read admin boundary	90	adminboundary_read
816	Can update admin boundary	90	adminboundary_update
817	Can delete admin boundary	90	adminboundary_delete
818	Can list admin boundary	90	adminboundary_list
819	Can create boundary alias	91	boundaryalias_create
820	Can read boundary alias	91	boundaryalias_read
821	Can update boundary alias	91	boundaryalias_update
822	Can delete boundary alias	91	boundaryalias_delete
823	Can list boundary alias	91	boundaryalias_list
824	Can create airtime transfer	92	airtimetransfer_create
825	Can read airtime transfer	92	airtimetransfer_read
826	Can update airtime transfer	92	airtimetransfer_update
827	Can delete airtime transfer	92	airtimetransfer_delete
828	Can list airtime transfer	92	airtimetransfer_list
829	Can refresh api token	15	apitoken_refresh
830	Can api resthook	16	resthook_api
831	Can api web hook event	18	webhookevent_api
832	Can api resthook subscriber	17	resthooksubscriber_api
833	Can api Campaign	86	campaign_api
834	Can archived Campaign	86	campaign_archived
835	Can archive Campaign	86	campaign_archive
836	Can activate Campaign	86	campaign_activate
837	Can menu Campaign	86	campaign_menu
838	Can api Campaign Event	87	campaignevent_api
839	Can connect classifier	20	classifier_connect
840	Can api classifier	20	classifier_api
841	Can sync classifier	20	classifier_sync
842	Can menu classifier	20	classifier_menu
843	Can api intent	21	intent_api
844	Can api contact	40	contact_api
845	Can archive contact	40	contact_archive
846	Can archived contact	40	contact_archived
847	Can block contact	40	contact_block
848	Can blocked contact	40	contact_blocked
849	Can break_anon contact	40	contact_break_anon
850	Can export contact	40	contact_export
851	Can stopped contact	40	contact_stopped
852	Can filter contact	40	contact_filter
853	Can history contact	40	contact_history
854	Can menu contact	40	contact_menu
855	Can omnibox contact	40	contact_omnibox
856	Can restore contact	40	contact_restore
857	Can search contact	40	contact_search
858	Can start contact	40	contact_start
859	Can update_fields contact	40	contact_update_fields
860	Can update_fields_input contact	40	contact_update_fields_input
861	Can api contact field	41	contactfield_api
862	Can json contact field	41	contactfield_json
863	Can menu contact field	41	contactfield_menu
864	Can update_priority contact field	41	contactfield_update_priority
865	Can featured contact field	41	contactfield_featured
866	Can filter_by_type contact field	41	contactfield_filter_by_type
867	Can api Group	42	contactgroup_api
868	Can menu Group	42	contactgroup_menu
869	Can preview contact import	44	contactimport_preview
870	Can start ivr call	89	ivrcall_start
871	Can api archive	14	archive_api
872	Can run archive	14	archive_run
873	Can message archive	14	archive_message
874	Can api global	22	global_api
875	Can unused global	22	global_unused
876	Can alias admin boundary	90	adminboundary_alias
877	Can api admin boundary	90	adminboundary_api
878	Can boundaries admin boundary	90	adminboundary_boundaries
879	Can geometry admin boundary	90	adminboundary_geometry
880	Can account org	30	org_account
881	Can accounts org	30	org_accounts
882	Can smtp_server org	30	org_smtp_server
883	Can api org	30	org_api
884	Can country org	30	org_country
885	Can clear_cache org	30	org_clear_cache
886	Can create_login org	30	org_create_login
887	Can create_sub_org org	30	org_create_sub_org
888	Can dashboard org	30	org_dashboard
889	Can download org	30	org_download
890	Can edit org	30	org_edit
891	Can edit_sub_org org	30	org_edit_sub_org
892	Can export org	30	org_export
893	Can grant org	30	org_grant
894	Can home org	30	org_home
895	Can import org	30	org_import
896	Can join org	30	org_join
897	Can join_accept org	30	org_join_accept
898	Can languages org	30	org_languages
899	Can manage org	30	org_manage
900	Can manage_accounts org	30	org_manage_accounts
901	Can manage_accounts_sub_org org	30	org_manage_accounts_sub_org
902	Can manage_integrations org	30	org_manage_integrations
903	Can menu org	30	org_menu
904	Can vonage_account org	30	org_vonage_account
905	Can vonage_connect org	30	org_vonage_connect
906	Can plan org	30	org_plan
907	Can plivo_connect org	30	org_plivo_connect
908	Can profile org	30	org_profile
909	Can prometheus org	30	org_prometheus
910	Can resthooks org	30	org_resthooks
911	Can service org	30	org_service
912	Can signup org	30	org_signup
913	Can spa org	30	org_spa
914	Can sub_orgs org	30	org_sub_orgs
915	Can surveyor org	30	org_surveyor
916	Can transfer_credits org	30	org_transfer_credits
917	Can trial org	30	org_trial
918	Can twilio_account org	30	org_twilio_account
919	Can twilio_connect org	30	org_twilio_connect
920	Can two_factor org	30	org_two_factor
921	Can token org	30	org_token
922	Can workspace org	30	org_workspace
923	Can api channel	49	channel_api
924	Can bulk_sender_options channel	49	channel_bulk_sender_options
925	Can claim channel	49	channel_claim
926	Can configuration channel	49	channel_configuration
927	Can create_bulk_sender channel	49	channel_create_bulk_sender
928	Can create_caller channel	49	channel_create_caller
929	Can errors channel	49	channel_errors
930	Can facebook_whitelist channel	49	channel_facebook_whitelist
931	Can menu channel	49	channel_menu
932	Can connection channel log	54	channellog_connection
933	Can api channel event	52	channelevent_api
934	Can calls channel event	52	channelevent_calls
935	Can api flow start	75	flowstart_api
936	Can activity Flow	66	flow_activity
937	Can activity_chart Flow	66	flow_activity_chart
938	Can activity_list Flow	66	flow_activity_list
939	Can api Flow	66	flow_api
940	Can archived Flow	66	flow_archived
941	Can assets Flow	66	flow_assets
942	Can broadcast Flow	66	flow_broadcast
943	Can campaign Flow	66	flow_campaign
944	Can category_counts Flow	66	flow_category_counts
945	Can change_language Flow	66	flow_change_language
946	Can copy Flow	66	flow_copy
947	Can editor Flow	66	flow_editor
948	Can export Flow	66	flow_export
949	Can export_translation Flow	66	flow_export_translation
950	Can download_translation Flow	66	flow_download_translation
951	Can import_translation Flow	66	flow_import_translation
952	Can export_results Flow	66	flow_export_results
953	Can filter Flow	66	flow_filter
954	Can menu Flow	66	flow_menu
955	Can recent_contacts Flow	66	flow_recent_contacts
956	Can results Flow	66	flow_results
957	Can revisions Flow	66	flow_revisions
958	Can run_table Flow	66	flow_run_table
959	Can simulate Flow	66	flow_simulate
960	Can upload_action_recording Flow	66	flow_upload_action_recording
961	Can upload_media_action Flow	66	flow_upload_media_action
962	Can json flow session	74	flowsession_json
963	Can api msg	57	msg_api
964	Can archive msg	57	msg_archive
965	Can archived msg	57	msg_archived
966	Can export msg	57	msg_export
967	Can failed msg	57	msg_failed
968	Can filter msg	57	msg_filter
969	Can flow msg	57	msg_flow
970	Can inbox msg	57	msg_inbox
971	Can label msg	57	msg_label
972	Can menu msg	57	msg_menu
973	Can outbox msg	57	msg_outbox
974	Can sent msg	57	msg_sent
975	Can api broadcast	55	broadcast_api
976	Can detail broadcast	55	broadcast_detail
977	Can schedule broadcast	55	broadcast_schedule
978	Can schedule_list broadcast	55	broadcast_schedule_list
979	Can schedule_read broadcast	55	broadcast_schedule_read
980	Can send broadcast	55	broadcast_send
981	Can api label	56	label_api
982	Can delete_folder label	56	label_delete_folder
983	Can manage top up	31	topup_manage
984	Can admin policy	25	policy_admin
985	Can history policy	25	policy_history
986	Can give_consent policy	25	policy_give_consent
987	Can webhooks http log	19	httplog_webhooks
988	Can classifier http log	19	httplog_classifier
989	Can ticketer http log	19	httplog_ticketer
990	Can api template	28	template_api
991	Can api ticket	77	ticket_api
992	Can assign ticket	77	ticket_assign
993	Can assignee ticket	77	ticket_assignee
994	Can menu ticket	77	ticket_menu
995	Can note ticket	77	ticket_note
996	Can export_stats ticket	77	ticket_export_stats
997	Can api ticketer	80	ticketer_api
998	Can connect ticketer	80	ticketer_connect
999	Can configure ticketer	80	ticketer_configure
1000	Can api topic	78	topic_api
1001	Can archived Trigger	85	trigger_archived
1002	Can type Trigger	85	trigger_type
1003	Can menu Trigger	85	trigger_menu
1004	Can add org membership	93	add_orgmembership
1005	Can change org membership	93	change_orgmembership
1006	Can delete org membership	93	delete_orgmembership
1007	Can view org membership	93	view_orgmembership
1008	Can create orgmembership	93	orgmembership_create
1009	Can read orgmembership	93	orgmembership_read
1010	Can update orgmembership	93	orgmembership_update
1011	Can delete orgmembership	93	orgmembership_delete
1012	Can list orgmembership	93	orgmembership_list
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	!HWIwMA07I4j1e8g6T7O5MAtgEFWyWNxt1KaQUWKG	\N	f	AnonymousUser				f	t	2022-06-19 12:11:34.970795+02
2	pbkdf2_sha256$320000$PCYUs1D4wZRFYRn6tTvVb0$+x2XNPND1tGYztyxgp/Jd/BKlezWh0hwDx86kREfHZk=	2022-06-19 19:57:46.575859+02	f	dev@mista.io	Alex	Bwanakweli	dev@mista.io	f	t	2022-06-19 12:12:57.275899+02
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: authtoken_token; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.authtoken_token (key, created, user_id) FROM stdin;
\.


--
-- Data for Name: campaigns_campaign; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.campaigns_campaign (id, is_active, created_on, modified_on, uuid, name, is_archived, created_by_id, group_id, modified_by_id, org_id, is_system) FROM stdin;
\.


--
-- Data for Name: campaigns_campaignevent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.campaigns_campaignevent (id, is_active, created_on, modified_on, uuid, event_type, "offset", unit, start_mode, message, delivery_hour, campaign_id, created_by_id, flow_id, modified_by_id, relative_to_id) FROM stdin;
\.


--
-- Data for Name: campaigns_eventfire; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.campaigns_eventfire (id, scheduled, fired, fired_result, contact_id, event_id) FROM stdin;
\.


--
-- Data for Name: channels_alert; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_alert (id, is_active, created_on, modified_on, alert_type, ended_on, channel_id, created_by_id, modified_by_id, sync_event_id) FROM stdin;
\.


--
-- Data for Name: channels_channel; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_channel (id, is_active, created_on, modified_on, uuid, channel_type, name, address, country, claim_code, secret, last_seen, device, os, alert_email, config, schemes, role, bod, tps, created_by_id, modified_by_id, org_id, parent_id, is_system) FROM stdin;
\.


--
-- Data for Name: channels_channelconnection; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_channelconnection (id, connection_type, direction, status, external_id, created_on, modified_on, started_on, ended_on, duration, error_reason, error_count, next_attempt, channel_id, contact_id, contact_urn_id, org_id) FROM stdin;
\.


--
-- Data for Name: channels_channelcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_channelcount (id, is_squashed, count_type, day, count, channel_id) FROM stdin;
\.


--
-- Data for Name: channels_channelevent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_channelevent (id, event_type, extra, occurred_on, created_on, channel_id, contact_id, contact_urn_id, org_id) FROM stdin;
\.


--
-- Data for Name: channels_channellog; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_channellog (id, description, is_error, url, method, request, response, response_status, created_on, request_time, channel_id, connection_id, msg_id) FROM stdin;
\.


--
-- Data for Name: channels_syncevent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.channels_syncevent (id, is_active, created_on, modified_on, power_source, power_status, power_level, network_type, lifetime, pending_message_count, retry_message_count, incoming_command_count, outgoing_command_count, channel_id, created_by_id, modified_by_id) FROM stdin;
\.


--
-- Data for Name: classifiers_classifier; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.classifiers_classifier (id, is_active, created_on, modified_on, uuid, classifier_type, name, config, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
\.


--
-- Data for Name: classifiers_intent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.classifiers_intent (id, is_active, name, external_id, created_on, classifier_id) FROM stdin;
\.


--
-- Data for Name: contacts_contact; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contact (id, is_active, created_on, modified_on, uuid, name, language, fields, status, ticket_count, last_seen_on, created_by_id, current_flow_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: contacts_contactfield; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactfield (id, is_active, created_on, modified_on, uuid, key, value_type, show_in_table, priority, created_by_id, modified_by_id, org_id, is_system, name) FROM stdin;
1	t	2022-06-19 12:12:57.628355+02	2022-06-19 12:12:57.628416+02	4e9126a6-ab5d-4756-8152-ab4ef85684b3	id	N	f	0	2	2	1	t	ID
2	t	2022-06-19 12:12:57.629451+02	2022-06-19 12:12:57.629495+02	0e331f96-28f3-4823-ba03-410a0d5954ae	name	T	f	0	2	2	1	t	Name
3	t	2022-06-19 12:12:57.63018+02	2022-06-19 12:12:57.630221+02	447fa58b-f0c9-4c71-86de-dd69848f59a9	created_on	D	f	0	2	2	1	t	Created On
4	t	2022-06-19 12:12:57.630882+02	2022-06-19 12:12:57.630921+02	4c59ac42-fdfd-414d-9b43-10e0fb242086	language	T	f	0	2	2	1	t	Language
5	t	2022-06-19 12:12:57.63156+02	2022-06-19 12:12:57.631598+02	e9329487-7aaf-4224-b38c-6366a64eefe7	last_seen_on	D	f	0	2	2	1	t	Last Seen On
\.


--
-- Data for Name: contacts_contactgroup; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactgroup (id, is_active, created_on, modified_on, uuid, name, group_type, status, query, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
1	t	2022-06-19 12:12:57.62291+02	2022-06-19 12:12:57.623+02	2979d240-3a77-44ec-b875-add241416562	Active	A	R	\N	2	2	1	t
2	t	2022-06-19 12:12:57.624192+02	2022-06-19 12:12:57.624244+02	84c01a6a-5350-4ca6-8eee-fefca985cc3c	Blocked	B	R	\N	2	2	1	t
3	t	2022-06-19 12:12:57.625005+02	2022-06-19 12:12:57.625059+02	a47f6c5b-45ba-490e-9bf1-03ae77606b28	Stopped	S	R	\N	2	2	1	t
4	t	2022-06-19 12:12:57.625738+02	2022-06-19 12:12:57.625787+02	56ca613c-1a0a-4eb9-a190-616c9c4d14e9	Archived	V	R	\N	2	2	1	t
5	t	2022-06-19 12:12:57.626456+02	2022-06-19 12:12:57.626505+02	ace1ff53-0ed5-4c53-9d36-35b25066816c	Open Tickets	Q	R	tickets > 0	2	2	1	t
\.


--
-- Data for Name: contacts_contactgroup_contacts; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactgroup_contacts (id, contactgroup_id, contact_id) FROM stdin;
\.


--
-- Data for Name: contacts_contactgroup_query_fields; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactgroup_query_fields (id, contactgroup_id, contactfield_id) FROM stdin;
\.


--
-- Data for Name: contacts_contactgroupcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactgroupcount (id, is_squashed, count, group_id) FROM stdin;
\.


--
-- Data for Name: contacts_contactimport; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactimport (id, is_active, created_on, modified_on, file, original_filename, mappings, num_records, group_name, started_on, status, finished_on, created_by_id, group_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: contacts_contactimportbatch; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contactimportbatch (id, status, specs, record_start, record_end, num_created, num_updated, num_errored, errors, finished_on, contact_import_id) FROM stdin;
\.


--
-- Data for Name: contacts_contacturn; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_contacturn (id, identity, scheme, path, display, priority, auth, channel_id, contact_id, org_id) FROM stdin;
\.


--
-- Data for Name: contacts_exportcontactstask; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_exportcontactstask (id, is_active, created_on, modified_on, uuid, status, search, created_by_id, group_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: contacts_exportcontactstask_group_memberships; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.contacts_exportcontactstask_group_memberships (id, exportcontactstask_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: csv_imports_importtask; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.csv_imports_importtask (id, is_active, created_on, modified_on, csv_file, model_class, import_params, import_log, import_results, task_id, created_by_id, modified_by_id, task_status) FROM stdin;
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	auth	permission
2	auth	group
3	auth	user
4	contenttypes	contenttype
5	sessions	session
6	sites	site
7	authtoken	token
8	authtoken	tokenproxy
9	csv_imports	importtask
10	users	failedlogin
11	users	passwordhistory
12	users	recoverytoken
13	apks	apk
14	archives	archive
15	api	apitoken
16	api	resthook
17	api	resthooksubscriber
18	api	webhookevent
19	request_logs	httplog
20	classifiers	classifier
21	classifiers	intent
22	globals	global
23	public	video
24	public	lead
25	policies	policy
26	policies	consent
27	schedules	schedule
28	templates	template
29	templates	templatetranslation
30	orgs	org
31	orgs	topup
32	orgs	usersettings
33	orgs	topupcredits
34	orgs	invitation
35	orgs	debit
36	orgs	creditalert
37	orgs	backuptoken
38	orgs	orgactivity
39	orgs	user
40	contacts	contact
41	contacts	contactfield
42	contacts	contactgroup
43	contacts	contactgroupcount
44	contacts	contactimport
45	contacts	contactimportbatch
46	contacts	contacturn
47	contacts	exportcontactstask
48	channels	alert
49	channels	channel
50	channels	channelconnection
51	channels	channelcount
52	channels	channelevent
53	channels	syncevent
54	channels	channellog
55	msgs	broadcast
56	msgs	label
57	msgs	msg
58	msgs	labelcount
59	msgs	exportmessagestask
60	msgs	broadcastmsgcount
61	msgs	systemlabelcount
62	notifications	incident
63	notifications	notificationcount
64	notifications	notification
65	flows	exportflowresultstask
66	flows	flow
67	flows	flowcategorycount
68	flows	flowlabel
69	flows	flownodecount
70	flows	flowpathcount
71	flows	flowrevision
72	flows	flowrun
73	flows	flowruncount
74	flows	flowsession
75	flows	flowstart
76	flows	flowstartcount
77	tickets	ticket
78	tickets	topic
79	tickets	ticketevent
80	tickets	ticketer
81	tickets	ticketcount
82	tickets	team
83	tickets	ticketdailycount
84	tickets	ticketdailytiming
85	triggers	trigger
86	campaigns	campaign
87	campaigns	campaignevent
88	campaigns	eventfire
89	ivr	ivrcall
90	locations	adminboundary
91	locations	boundaryalias
92	airtime	airtimetransfer
93	orgs	orgmembership
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2022-06-19 12:11:31.222498+02
2	auth	0001_initial	2022-06-19 12:11:31.38337+02
3	locations	0024_squashed	2022-06-19 12:11:31.490894+02
4	orgs	0093_squashed	2022-06-19 12:11:32.107839+02
5	contacts	0152_squashed	2022-06-19 12:11:32.361641+02
6	airtime	0019_squashed	2022-06-19 12:11:32.387022+02
7	airtime	0020_squashed	2022-06-19 12:11:32.416255+02
8	airtime	0021_squashed	2022-06-19 12:11:32.467649+02
9	tickets	0027_squashed	2022-06-19 12:11:33.133005+02
10	tickets	0028_alter_topic_name	2022-06-19 12:11:33.188489+02
11	tickets	0029_alter_ticketer_name_alter_ticketer_uuid	2022-06-19 12:11:33.237682+02
12	tickets	0030_topic_unique_topic_names	2022-06-19 12:11:33.279193+02
13	orgs	0094_alter_org_parent	2022-06-19 12:11:33.399539+02
14	tickets	0031_team_ticketdailycount_and_more	2022-06-19 12:11:33.638659+02
15	orgs	0095_usersettings_team	2022-06-19 12:11:33.696738+02
16	contenttypes	0002_remove_content_type_name	2022-06-19 12:11:33.739176+02
17	auth	0002_alter_permission_name_max_length	2022-06-19 12:11:33.76582+02
18	auth	0003_alter_user_email_max_length	2022-06-19 12:11:33.79302+02
19	auth	0004_alter_user_username_opts	2022-06-19 12:11:33.817512+02
20	auth	0005_alter_user_last_login_null	2022-06-19 12:11:33.842391+02
21	auth	0006_require_contenttypes_0002	2022-06-19 12:11:33.844778+02
22	auth	0007_alter_validators_add_error_messages	2022-06-19 12:11:33.870971+02
23	auth	0008_alter_user_username_max_length	2022-06-19 12:11:34.000479+02
24	auth	0009_alter_user_last_name_max_length	2022-06-19 12:11:34.037785+02
25	auth	0010_alter_group_name_max_length	2022-06-19 12:11:34.066759+02
26	auth	0011_update_proxy_permissions	2022-06-19 12:11:34.098353+02
27	auth	0012_alter_user_first_name_max_length	2022-06-19 12:11:34.128126+02
28	orgs	0096_user	2022-06-19 12:11:34.170812+02
29	api	0036_squashed	2022-06-19 12:11:34.245389+02
30	api	0037_squashed	2022-06-19 12:11:34.708994+02
31	api	0038_alter_apitoken_user	2022-06-19 12:11:34.749853+02
32	api	0039_alter_apitoken_created	2022-06-19 12:11:34.777788+02
33	apks	0005_squashed	2022-06-19 12:11:34.801338+02
34	archives	0015_squashed	2022-06-19 12:11:34.816348+02
35	archives	0016_squashed	2022-06-19 12:11:34.917728+02
36	auth_tweaks	0001_initial	2022-06-19 12:11:34.925008+02
37	auth_tweaks	0002_ensure_anon_user	2022-06-19 12:11:34.972402+02
38	authtoken	0001_initial	2022-06-19 12:11:35.027+02
39	authtoken	0002_auto_20160226_1747	2022-06-19 12:11:35.245054+02
40	authtoken	0003_tokenproxy	2022-06-19 12:11:35.25459+02
41	channels	0137_squashed	2022-06-19 12:11:35.542557+02
42	campaigns	0042_squashed	2022-06-19 12:11:35.623902+02
43	campaigns	0043_squashed	2022-06-19 12:11:35.797348+02
44	flows	0278_squashed	2022-06-19 12:11:36.38975+02
45	campaigns	0044_squashed	2022-06-19 12:11:36.690127+02
46	campaigns	0045_squashed	2022-06-19 12:11:36.774616+02
47	campaigns	0046_alter_campaign_name	2022-06-19 12:11:36.84415+02
48	campaigns	0047_alter_campaign_uuid_alter_campaignevent_uuid	2022-06-19 12:11:37.10644+02
49	campaigns	0048_campaign_is_system	2022-06-19 12:11:37.172092+02
50	schedules	0017_squashed	2022-06-19 12:11:37.293972+02
51	contacts	0153_squashed	2022-06-19 12:11:38.862547+02
52	msgs	0169_squashed	2022-06-19 12:11:40.158644+02
53	channels	0138_squashed	2022-06-19 12:11:41.691233+02
54	channels	0139_channel_is_system	2022-06-19 12:11:41.769643+02
55	classifiers	0006_squashed	2022-06-19 12:11:42.03799+02
56	classifiers	0007_squashed	2022-06-19 12:11:42.12501+02
57	classifiers	0008_alter_classifier_name_alter_classifier_uuid	2022-06-19 12:11:42.297863+02
58	classifiers	0009_classifier_is_system	2022-06-19 12:11:42.356849+02
59	contacts	0154_contactgroup_is_system	2022-06-19 12:11:42.544276+02
60	contacts	0155_populate_is_system	2022-06-19 12:11:42.61404+02
61	contacts	0156_alter_contactgroup_group_type_and_more	2022-06-19 12:11:42.733336+02
62	contacts	0157_update_group_type	2022-06-19 12:11:42.801481+02
63	contacts	0158_alter_contactgroup_managers_and_more	2022-06-19 12:11:43.09129+02
64	contacts	0159_open_tickets_sys_groups	2022-06-19 12:11:43.162161+02
65	contacts	0160_contactfield_is_system_contactfield_name	2022-06-19 12:11:43.263481+02
66	contacts	0161_populate_field_name_and_is_system	2022-06-19 12:11:43.326141+02
67	contacts	0162_alter_contactfield_field_type_and_more	2022-06-19 12:11:43.677065+02
68	contacts	0163_alter_contactgroup_name	2022-06-19 12:11:43.736709+02
69	contacts	0164_remove_contactfield_field_type_and_more	2022-06-19 12:11:43.83366+02
70	contacts	0165_alter_contactfield_managers	2022-06-19 12:11:44.046411+02
71	contacts	0166_fix_invalid_names	2022-06-19 12:11:44.11868+02
72	contacts	0167_alter_contactgroup_is_system	2022-06-19 12:11:44.196056+02
73	csv_imports	0001_initial	2022-06-19 12:11:44.285182+02
74	csv_imports	0002_auto_20161118_1920	2022-06-19 12:11:44.448621+02
75	csv_imports	0003_importtask_task_status	2022-06-19 12:11:44.508494+02
76	csv_imports	0004_auto_20170223_0917	2022-06-19 12:11:44.601347+02
77	csv_imports	0005_alter_importtask_created_by_and_more	2022-06-19 12:11:44.711966+02
78	templates	0012_squashed	2022-06-19 12:11:44.988071+02
79	globals	0006_squashed	2022-06-19 12:11:45.093534+02
80	globals	0007_squashed	2022-06-19 12:11:45.184314+02
81	flows	0279_squashed	2022-06-19 12:11:49.903386+02
82	flows	0280_alter_flowrun_contact_and_more	2022-06-19 12:11:50.077096+02
83	flows	0281_update_deleted_flow_names	2022-06-19 12:11:50.160563+02
84	flows	0282_alter_flow_name	2022-06-19 12:11:50.244564+02
85	flows	0283_unique_flow_names	2022-06-19 12:11:50.487363+02
86	flows	0284_flow_unique_flow_names	2022-06-19 12:11:50.572642+02
87	flows	0285_fix_invalid_names	2022-06-19 12:11:50.656597+02
88	flows	0286_alter_flow_name	2022-06-19 12:11:50.740828+02
89	flows	0287_alter_flowlabel_unique_together_flowlabel_created_by_and_more	2022-06-19 12:11:51.56483+02
90	flows	0288_flowlabel_is_system	2022-06-19 12:11:51.64839+02
91	globals	0008_global_is_system_alter_global_uuid	2022-06-19 12:11:51.917359+02
92	ivr	0018_squashed	2022-06-19 12:11:51.922716+02
93	locations	0025_squashed	2022-06-19 12:11:52.086255+02
94	msgs	0170_alter_label_name	2022-06-19 12:11:52.177907+02
95	msgs	0171_update_deleted_label_names	2022-06-19 12:11:52.255765+02
96	msgs	0172_label_unique_label_names	2022-06-19 12:11:52.467683+02
97	msgs	0173_label_is_system	2022-06-19 12:11:52.546113+02
98	msgs	0174_alter_label_managers	2022-06-19 12:11:52.630643+02
99	msgs	0175_alter_msg_failed_reason	2022-06-19 12:11:52.716539+02
100	notifications	0008_squashed	2022-06-19 12:11:53.842454+02
101	orgs	0097_alter_backuptoken_user_alter_org_administrators_and_more	2022-06-19 12:11:54.73058+02
102	orgs	0098_alter_org_brand	2022-06-19 12:11:54.815436+02
103	policies	0008_squashed	2022-06-19 12:11:55.040245+02
104	public	0010_squashed	2022-06-19 12:11:55.404778+02
105	request_logs	0014_squashed	2022-06-19 12:11:55.740089+02
106	sessions	0001_initial	2022-06-19 12:11:55.777661+02
107	sites	0001_initial	2022-06-19 12:11:55.801095+02
108	sites	0002_alter_domain_unique	2022-06-19 12:11:55.835747+02
109	sql	0004_squashed	2022-06-19 12:11:56.054932+02
110	tickets	0032_team_is_system_ticketer_is_system_topic_is_system	2022-06-19 12:11:56.431386+02
111	tickets	0033_populate_is_system	2022-06-19 12:11:56.52338+02
112	tickets	0034_backfill_ticket_daily_counts	2022-06-19 12:11:56.617398+02
113	tickets	0035_ticketdailytiming_ticket_replied_on_and_more	2022-06-19 12:11:56.875449+02
114	tickets	0036_backfill_ticket_reply_timings	2022-06-19 12:11:56.968762+02
115	tickets	0037_alter_ticket_assignee_alter_ticketcount_assignee_and_more	2022-06-19 12:11:57.221671+02
116	triggers	0023_squashed	2022-06-19 12:11:57.60517+02
117	triggers	0024_alter_trigger_options	2022-06-19 12:11:57.71933+02
118	users	0001_initial	2022-06-19 12:11:58.032222+02
119	users	0002_remove_failed_logins	2022-06-19 12:11:58.288801+02
120	users	0003_auto_20210219_1548	2022-06-19 12:11:58.39485+02
121	orgs	0098_orgmembership_org_users_orgmembership_org_and_more	2022-06-19 19:19:27.493611+02
122	orgs	0099_backfill_org_membership	2022-06-19 19:19:27.598476+02
123	orgs	0100_alter_org_users	2022-06-19 19:19:27.814148+02
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
on8cgm2ipqw78h5buu6zz8mzhyw4wul3	.eJxVi8sOwiAQRf-FtSE8ysud_REyA1MhxjYpdGX8dzHpQlc3OfecF4tw9BKPRnusmV2ZYpdfhpAetH6PTk8Evu33xk_Ib0OjtdcEvW7rfKp_fYFWRuxwIo-Uxwipg3BOg7cGiWRaQsgWPBhSxiIgSD_loKwGlUjYgGbR7P0B0Ek4RA:1o2rvN:3VC9EI9bCCPZQfIlNPfaC9bqaEhXz4tyS-Yk0Z2Ps5E	2022-07-03 12:12:57.661466+02
szizn37ls4aii0frxbrldomu8fn5v8wy	.eJxVTkkOwiAUvQtrQxjK5E4vQv6HXyHGNil0Zby7aLrQ1Uve_GQR9l7i3miLNbMzU-z0yyGkOy0fodMDga_brfGD5Jdho6XXBL2uy_Ww_uULtDLCDifySHmAkDoI5zR4a5BIpjmEbMGDIWUsAoL0Uw7KalCJhA1oZj1Kx_L3oXy9AU20O5M:1o2t4t:iA9nq4-bAzIQEsmfH9MYBwJHzXZ4vYaUlVNo372AFpM	2022-07-03 13:26:51.468707+02
94ggih7pltwkclae5fx7hnnyimmqr6gs	.eJxVTkkOwiAUvQtrQxjK5E4vQv6HXyHGNil0Zby7aLrQ1Uve_GQR9l7i3miLNbMzU-z0yyGkOy0fodMDga_brfGD5Jdho6XXBL2uy_Ww_uULtDLCDifySHmAkDoI5zR4a5BIpjmEbMGDIWUsAoL0Uw7KalCJhA1oZj1Kx_L3oXy9AU20O5M:1o2vD9:eCE7oLzAY79tuNcRmfDHwW9iPKoiBdsgtnROQ7w5uwU	2022-07-03 15:43:31.877234+02
116l2kysfqy0q6imgmbdn7rcolzgdrgh	.eJxVTkkOwiAUvQtrQxjK5E4vQv6HXyHGNil0Zby7aLrQ1Uve_GQR9l7i3miLNbMzU-z0yyGkOy0fodMDga_brfGD5Jdho6XXBL2uy_Ww_uULtDLCDifySHmAkDoI5zR4a5BIpjmEbMGDIWUsAoL0Uw7KalCJhA1oZj1Kx_L3oXy9AU20O5M:1o2zBE:AZtX67BH78Bd2AotiFDm_CXMpQZSWop-5C_XgqQ2_F8	2022-07-03 19:57:48.768555+02
\.


--
-- Data for Name: django_site; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.django_site (id, domain, name) FROM stdin;
1	example.com	example.com
\.


--
-- Data for Name: flows_exportflowresultstask; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_exportflowresultstask (id, is_active, created_on, modified_on, uuid, status, config, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: flows_exportflowresultstask_flows; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_exportflowresultstask_flows (id, exportflowresultstask_id, flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flow; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow (id, is_active, created_on, modified_on, uuid, name, is_archived, is_system, flow_type, metadata, expires_after_minutes, ignore_triggers, saved_on, base_language, version_number, has_issues, created_by_id, modified_by_id, org_id, saved_by_id) FROM stdin;
13	t	2022-06-19 19:19:52.57356+02	2022-06-19 19:27:45.685301+02	fc86982f-b25b-4bf3-a2bb-1c62db21e790	weeb	f	f	M	{"results": [{"key": "result_1", "name": "Result 1", "categories": ["1", "Other"], "node_uuids": ["a15f5bfe-e37a-417f-b7da-905f5b481866"]}], "dependencies": [], "waiting_exit_uuids": ["2d96523c-e04b-41fa-bbec-c86e76b1926e", "50150bc6-4be6-4f66-93c4-3e9c2e09ff37"], "parent_refs": []}	10080	f	2022-06-19 19:27:45.685296+02	eng	13.1.0	f	2	2	1	2
\.


--
-- Data for Name: flows_flow_channel_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_channel_dependencies (id, flow_id, channel_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_classifier_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_classifier_dependencies (id, flow_id, classifier_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_field_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_field_dependencies (id, flow_id, contactfield_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_flow_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_flow_dependencies (id, from_flow_id, to_flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_global_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_global_dependencies (id, flow_id, global_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_group_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_group_dependencies (id, flow_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_label_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_label_dependencies (id, flow_id, label_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_labels; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_labels (id, flow_id, flowlabel_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_template_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_template_dependencies (id, flow_id, template_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_ticketer_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_ticketer_dependencies (id, flow_id, ticketer_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_topic_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_topic_dependencies (id, flow_id, topic_id) FROM stdin;
\.


--
-- Data for Name: flows_flow_user_dependencies; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flow_user_dependencies (id, flow_id, user_id) FROM stdin;
\.


--
-- Data for Name: flows_flowcategorycount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowcategorycount (id, is_squashed, node_uuid, result_key, result_name, category_name, count, flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flowlabel; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowlabel (id, uuid, name, org_id, parent_id, created_by_id, created_on, is_active, modified_by_id, modified_on, is_system) FROM stdin;
\.


--
-- Data for Name: flows_flownodecount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flownodecount (id, is_squashed, node_uuid, count, flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flowpathcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowpathcount (id, is_squashed, from_uuid, to_uuid, period, count, flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flowrevision; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowrevision (id, is_active, created_on, modified_on, definition, spec_version, revision, created_by_id, flow_id, modified_by_id) FROM stdin;
1	t	2022-06-19 19:19:52.595862+02	2022-06-19 19:19:52.595899+02	{"name": "weeb", "uuid": "fc86982f-b25b-4bf3-a2bb-1c62db21e790", "spec_version": "13.1.0", "language": "eng", "type": "messaging", "nodes": [], "_ui": {}, "revision": 1, "expire_after_minutes": 10080}	13.1.0	1	2	13	2
2	t	2022-06-19 19:27:37.64468+02	2022-06-19 19:27:37.644712+02	{"name": "weeb", "uuid": "fc86982f-b25b-4bf3-a2bb-1c62db21e790", "spec_version": "13.1.0", "language": "eng", "type": "messaging", "nodes": [{"uuid": "931174dc-58b5-44ba-8909-6d92ee5018fc", "actions": [{"attachments": [], "text": "welcome", "type": "send_msg", "quick_replies": [], "uuid": "ff38081b-bc6c-45ff-94bd-6cfcf30ad95c"}], "exits": [{"uuid": "9659046d-460d-44f2-b01d-343ecf885725", "destination_uuid": null}]}], "_ui": {"nodes": {"931174dc-58b5-44ba-8909-6d92ee5018fc": {"position": {"left": 0, "top": 0}, "type": "execute_actions"}}}, "revision": 2, "expire_after_minutes": 10080, "localization": {}}	13.1.0	2	2	13	2
3	t	2022-06-19 19:27:45.686411+02	2022-06-19 19:27:45.686443+02	{"name": "weeb", "uuid": "fc86982f-b25b-4bf3-a2bb-1c62db21e790", "spec_version": "13.1.0", "language": "eng", "type": "messaging", "nodes": [{"uuid": "931174dc-58b5-44ba-8909-6d92ee5018fc", "actions": [{"attachments": [], "text": "welcome", "type": "send_msg", "quick_replies": [], "uuid": "ff38081b-bc6c-45ff-94bd-6cfcf30ad95c"}], "exits": [{"uuid": "9659046d-460d-44f2-b01d-343ecf885725", "destination_uuid": "a15f5bfe-e37a-417f-b7da-905f5b481866"}]}, {"uuid": "a15f5bfe-e37a-417f-b7da-905f5b481866", "actions": [], "router": {"type": "switch", "default_category_uuid": "4a0b14a9-0cb3-42b3-9de1-dd7ee94a77e1", "cases": [{"arguments": ["1"], "type": "has_any_word", "uuid": "2f62bcda-27bb-4b69-9fab-0324abd44eb6", "category_uuid": "5d0a5e60-7a03-432f-b9e5-67a7a88d6117"}], "categories": [{"uuid": "5d0a5e60-7a03-432f-b9e5-67a7a88d6117", "name": "1", "exit_uuid": "2d96523c-e04b-41fa-bbec-c86e76b1926e"}, {"uuid": "4a0b14a9-0cb3-42b3-9de1-dd7ee94a77e1", "name": "Other", "exit_uuid": "50150bc6-4be6-4f66-93c4-3e9c2e09ff37"}], "operand": "@input.text", "wait": {"type": "msg"}, "result_name": "Result 1"}, "exits": [{"uuid": "2d96523c-e04b-41fa-bbec-c86e76b1926e"}, {"uuid": "50150bc6-4be6-4f66-93c4-3e9c2e09ff37", "destination_uuid": null}]}], "_ui": {"nodes": {"931174dc-58b5-44ba-8909-6d92ee5018fc": {"position": {"left": 0, "top": 0}, "type": "execute_actions"}, "a15f5bfe-e37a-417f-b7da-905f5b481866": {"type": "wait_for_response", "position": {"left": 320, "top": 340}, "config": {"cases": {}}}}}, "revision": 3, "expire_after_minutes": 10080, "localization": {}}	13.1.0	3	2	13	2
\.


--
-- Data for Name: flows_flowrun; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowrun (id, uuid, status, created_on, modified_on, exited_on, responded, results, path, current_node_uuid, delete_from_results, contact_id, flow_id, org_id, session_id, start_id, submitted_by_id) FROM stdin;
\.


--
-- Data for Name: flows_flowruncount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowruncount (id, is_squashed, exit_type, count, flow_id) FROM stdin;
\.


--
-- Data for Name: flows_flowsession; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowsession (id, uuid, status, session_type, responded, output, output_url, created_on, ended_on, wait_started_on, timeout_on, wait_expires_on, wait_resume_on_expire, connection_id, contact_id, current_flow_id, org_id) FROM stdin;
\.


--
-- Data for Name: flows_flowstart; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowstart (id, uuid, start_type, urns, query, restart_participants, include_active, status, extra, parent_summary, session_history, created_on, modified_on, contact_count, campaign_event_id, created_by_id, flow_id, org_id) FROM stdin;
\.


--
-- Data for Name: flows_flowstart_connections; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowstart_connections (id, flowstart_id, channelconnection_id) FROM stdin;
\.


--
-- Data for Name: flows_flowstart_contacts; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowstart_contacts (id, flowstart_id, contact_id) FROM stdin;
\.


--
-- Data for Name: flows_flowstart_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowstart_groups (id, flowstart_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: flows_flowstartcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.flows_flowstartcount (id, is_squashed, count, start_id) FROM stdin;
\.


--
-- Data for Name: globals_global; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.globals_global (id, is_active, created_on, modified_on, uuid, key, name, value, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
\.


--
-- Data for Name: locations_adminboundary; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.locations_adminboundary (id, osm_id, name, level, path, simplified_geometry, lft, rght, tree_id, parent_id) FROM stdin;
\.


--
-- Data for Name: locations_boundaryalias; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.locations_boundaryalias (id, is_active, created_on, modified_on, name, boundary_id, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: msgs_broadcast; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_broadcast (id, raw_urns, base_language, text, media, status, created_on, modified_on, send_all, metadata, channel_id, created_by_id, modified_by_id, org_id, parent_id, schedule_id, ticket_id) FROM stdin;
\.


--
-- Data for Name: msgs_broadcast_contacts; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_broadcast_contacts (id, broadcast_id, contact_id) FROM stdin;
\.


--
-- Data for Name: msgs_broadcast_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_broadcast_groups (id, broadcast_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: msgs_broadcast_urns; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_broadcast_urns (id, broadcast_id, contacturn_id) FROM stdin;
\.


--
-- Data for Name: msgs_broadcastmsgcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_broadcastmsgcount (id, is_squashed, count, broadcast_id) FROM stdin;
\.


--
-- Data for Name: msgs_exportmessagestask; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_exportmessagestask (id, is_active, created_on, modified_on, uuid, status, system_label, start_date, end_date, created_by_id, label_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: msgs_exportmessagestask_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_exportmessagestask_groups (id, exportmessagestask_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: msgs_label; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_label (id, is_active, created_on, modified_on, uuid, name, label_type, created_by_id, folder_id, modified_by_id, org_id, is_system) FROM stdin;
\.


--
-- Data for Name: msgs_labelcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_labelcount (id, is_squashed, is_archived, count, label_id) FROM stdin;
\.


--
-- Data for Name: msgs_msg; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_msg (id, uuid, text, attachments, high_priority, created_on, modified_on, sent_on, queued_on, msg_type, direction, status, visibility, msg_count, error_count, next_attempt, failed_reason, external_id, metadata, broadcast_id, channel_id, contact_id, contact_urn_id, flow_id, org_id, topup_id) FROM stdin;
\.


--
-- Data for Name: msgs_msg_labels; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_msg_labels (id, msg_id, label_id) FROM stdin;
\.


--
-- Data for Name: msgs_systemlabelcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.msgs_systemlabelcount (id, is_squashed, label_type, is_archived, count, org_id) FROM stdin;
\.


--
-- Data for Name: notifications_incident; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.notifications_incident (id, incident_type, scope, started_on, ended_on, channel_id, org_id) FROM stdin;
\.


--
-- Data for Name: notifications_notification; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.notifications_notification (id, notification_type, scope, is_seen, email_status, created_on, contact_export_id, contact_import_id, incident_id, message_export_id, org_id, results_export_id, user_id) FROM stdin;
\.


--
-- Data for Name: notifications_notificationcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.notifications_notificationcount (id, is_squashed, count, org_id, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_backuptoken; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_backuptoken (id, token, is_used, created_on, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_creditalert; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_creditalert (id, is_active, created_on, modified_on, alert_type, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: orgs_debit; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_debit (id, amount, debit_type, created_on, beneficiary_id, created_by_id, topup_id) FROM stdin;
\.


--
-- Data for Name: orgs_invitation; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_invitation (id, is_active, created_on, modified_on, email, secret, user_group, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: orgs_org; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org (id, is_active, created_on, modified_on, uuid, name, plan, plan_start, plan_end, stripe_customer, language, timezone, date_format, config, slug, limits, api_rates, is_anon, is_flagged, is_suspended, uses_topups, is_multi_org, is_multi_user, flow_languages, brand, surveyor_password, released_on, deleted_on, country_id, created_by_id, modified_by_id, parent_id) FROM stdin;
1	t	2022-06-19 12:12:57.268129+02	2022-06-19 12:12:57.450376+02	24e88728-62e0-45aa-901e-34f31fa85e19	MISTA LLC	topups	\N	\N	\N	en-us	Africa/Johannesburg	D	\N	\N	{}	{}	f	f	f	t	t	t	{eng}	flowartisan.com	\N	\N	\N	\N	2	2	\N
\.


--
-- Data for Name: orgs_org_administrators; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org_administrators (id, org_id, user_id) FROM stdin;
1	1	2
\.


--
-- Data for Name: orgs_org_agents; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org_agents (id, org_id, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_org_editors; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org_editors (id, org_id, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_org_surveyors; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org_surveyors (id, org_id, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_org_viewers; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_org_viewers (id, org_id, user_id) FROM stdin;
\.


--
-- Data for Name: orgs_orgactivity; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_orgactivity (id, day, contact_count, active_contact_count, outgoing_count, incoming_count, plan_active_contact_count, org_id) FROM stdin;
\.


--
-- Data for Name: orgs_orgmembership; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_orgmembership (id, role_code, org_id, user_id) FROM stdin;
1	A	1	2
\.


--
-- Data for Name: orgs_topup; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_topup (id, is_active, created_on, modified_on, price, credits, expires_on, stripe_charge, comment, created_by_id, modified_by_id, org_id) FROM stdin;
1	t	2022-06-19 12:12:57.63682+02	2022-06-19 12:12:57.636893+02	0	500	2023-06-19 12:12:57.636714+02	\N	\N	2	2	1
\.


--
-- Data for Name: orgs_topupcredits; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_topupcredits (id, is_squashed, used, topup_id) FROM stdin;
\.


--
-- Data for Name: orgs_usersettings; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.orgs_usersettings (id, language, otp_secret, two_factor_enabled, last_auth_on, external_id, verification_token, user_id, team_id) FROM stdin;
1	en-us	B4A6JOIWIWMDLAZG	f	2022-06-19 19:57:46.573366+02	\N	\N	2	\N
\.


--
-- Data for Name: policies_consent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.policies_consent (id, revoked_on, created_on, policy_id, user_id) FROM stdin;
\.


--
-- Data for Name: policies_policy; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.policies_policy (id, is_active, created_on, modified_on, policy_type, body, summary, requires_consent, created_by_id, modified_by_id) FROM stdin;
\.


--
-- Data for Name: public_lead; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.public_lead (id, is_active, created_on, modified_on, email, created_by_id, modified_by_id) FROM stdin;
\.


--
-- Data for Name: public_video; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.public_video (id, is_active, created_on, modified_on, name, summary, description, vimeo_id, "order", created_by_id, modified_by_id) FROM stdin;
\.


--
-- Data for Name: request_logs_httplog; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.request_logs_httplog (id, log_type, url, status_code, request, response, request_time, num_retries, created_on, is_error, airtime_transfer_id, channel_id, classifier_id, flow_id, org_id, ticketer_id) FROM stdin;
\.


--
-- Data for Name: schedules_schedule; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.schedules_schedule (id, is_active, created_on, modified_on, repeat_period, repeat_hour_of_day, repeat_minute_of_hour, repeat_day_of_month, repeat_days_of_week, next_fire, last_fire, created_by_id, modified_by_id, org_id) FROM stdin;
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: templates_template; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.templates_template (id, uuid, name, modified_on, created_on, org_id) FROM stdin;
\.


--
-- Data for Name: templates_templatetranslation; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.templates_templatetranslation (id, content, variable_count, status, language, country, namespace, external_id, is_active, channel_id, template_id) FROM stdin;
\.


--
-- Data for Name: tickets_team; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_team (id, is_active, created_on, modified_on, uuid, name, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
\.


--
-- Data for Name: tickets_team_topics; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_team_topics (id, team_id, topic_id) FROM stdin;
\.


--
-- Data for Name: tickets_ticket; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticket (id, uuid, body, external_id, config, status, opened_on, closed_on, modified_on, last_activity_on, assignee_id, contact_id, org_id, ticketer_id, topic_id, replied_on) FROM stdin;
\.


--
-- Data for Name: tickets_ticketcount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticketcount (id, is_squashed, status, count, assignee_id, org_id) FROM stdin;
\.


--
-- Data for Name: tickets_ticketdailycount; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticketdailycount (id, is_squashed, count_type, scope, count, day) FROM stdin;
\.


--
-- Data for Name: tickets_ticketdailytiming; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticketdailytiming (id, is_squashed, count_type, scope, count, day, seconds) FROM stdin;
\.


--
-- Data for Name: tickets_ticketer; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticketer (id, is_active, created_on, modified_on, uuid, ticketer_type, name, config, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
1	t	2022-06-19 12:12:57.633744+02	2022-06-19 12:12:57.633782+02	574ac274-ed5b-4194-96f7-b88aa5736a04	internal	Flow Artisan Tickets	{}	2	2	1	t
\.


--
-- Data for Name: tickets_ticketevent; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_ticketevent (id, event_type, note, created_on, assignee_id, contact_id, created_by_id, org_id, ticket_id, topic_id) FROM stdin;
\.


--
-- Data for Name: tickets_topic; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.tickets_topic (id, is_active, created_on, modified_on, uuid, name, is_default, created_by_id, modified_by_id, org_id, is_system) FROM stdin;
1	t	2022-06-19 12:12:57.635905+02	2022-06-19 12:12:57.63595+02	adbf9cc1-5955-408d-82c2-cc8689a5e4a1	General	t	2	2	1	t
\.


--
-- Data for Name: triggers_trigger; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.triggers_trigger (id, is_active, created_on, modified_on, trigger_type, is_archived, keyword, referrer_id, match_type, channel_id, created_by_id, flow_id, modified_by_id, org_id, schedule_id) FROM stdin;
1	t	2022-06-19 19:19:52.634432+02	2022-06-19 19:19:52.634578+02	K	f	wwe	\N	F	\N	2	13	2	1	\N
\.


--
-- Data for Name: triggers_trigger_contacts; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.triggers_trigger_contacts (id, trigger_id, contact_id) FROM stdin;
\.


--
-- Data for Name: triggers_trigger_exclude_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.triggers_trigger_exclude_groups (id, trigger_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: triggers_trigger_groups; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.triggers_trigger_groups (id, trigger_id, contactgroup_id) FROM stdin;
\.


--
-- Data for Name: users_failedlogin; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.users_failedlogin (id, failed_on, username) FROM stdin;
1	2022-06-19 12:12:25.839885+02	alex@mista.io
2	2022-06-19 13:26:20.840918+02	alex@mista.io
3	2022-06-19 13:26:29.11327+02	alex@mista.io
\.


--
-- Data for Name: users_passwordhistory; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.users_passwordhistory (id, password, set_on, user_id) FROM stdin;
\.


--
-- Data for Name: users_recoverytoken; Type: TABLE DATA; Schema: public; Owner: flowartisan
--

COPY public.users_recoverytoken (id, token, created_on, user_id) FROM stdin;
\.


--
-- Data for Name: topology; Type: TABLE DATA; Schema: topology; Owner: postgres
--

COPY topology.topology (id, name, srid, "precision", hasz) FROM stdin;
\.


--
-- Data for Name: layer; Type: TABLE DATA; Schema: topology; Owner: postgres
--

COPY topology.layer (topology_id, layer_id, schema_name, table_name, feature_column, feature_type, level, child_id) FROM stdin;
\.


--
-- Name: airtime_airtimetransfer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.airtime_airtimetransfer_id_seq', 1, false);


--
-- Name: api_resthook_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.api_resthook_id_seq', 1, false);


--
-- Name: api_resthooksubscriber_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.api_resthooksubscriber_id_seq', 1, false);


--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.api_webhookevent_id_seq', 1, false);


--
-- Name: apks_apk_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.apks_apk_id_seq', 1, false);


--
-- Name: archives_archive_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.archives_archive_id_seq', 1, false);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 12, true);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 2031, true);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 1012, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 2, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.campaigns_campaign_id_seq', 1, false);


--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.campaigns_campaignevent_id_seq', 1, false);


--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.campaigns_eventfire_id_seq', 1, false);


--
-- Name: channels_alert_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_alert_id_seq', 1, false);


--
-- Name: channels_channel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_channel_id_seq', 1, false);


--
-- Name: channels_channelconnection_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_channelconnection_id_seq', 1, false);


--
-- Name: channels_channelcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_channelcount_id_seq', 1, false);


--
-- Name: channels_channelevent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_channelevent_id_seq', 1, false);


--
-- Name: channels_channellog_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_channellog_id_seq', 1, false);


--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.channels_syncevent_id_seq', 1, false);


--
-- Name: classifiers_classifier_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.classifiers_classifier_id_seq', 1, false);


--
-- Name: classifiers_intent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.classifiers_intent_id_seq', 1, false);


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contact_id_seq', 1, false);


--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactfield_id_seq', 5, true);


--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactgroup_contacts_id_seq', 1, false);


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactgroup_id_seq', 5, true);


--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactgroup_query_fields_id_seq', 1, false);


--
-- Name: contacts_contactgroupcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactgroupcount_id_seq', 1, false);


--
-- Name: contacts_contactimport_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactimport_id_seq', 1, false);


--
-- Name: contacts_contactimportbatch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contactimportbatch_id_seq', 1, false);


--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_contacturn_id_seq', 1, false);


--
-- Name: contacts_exportcontactstask_group_memberships_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_exportcontactstask_group_memberships_id_seq', 1, false);


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.contacts_exportcontactstask_id_seq', 1, false);


--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.csv_imports_importtask_id_seq', 1, false);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 93, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 123, true);


--
-- Name: django_site_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.django_site_id_seq', 1, true);


--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_exportflowresultstask_flows_id_seq', 1, false);


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_exportflowresultstask_id_seq', 1, false);


--
-- Name: flows_flow_channel_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_channel_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_classifier_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_classifier_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_field_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_field_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_flow_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_flow_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_global_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_global_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_group_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_group_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_id_seq', 13, true);


--
-- Name: flows_flow_label_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_label_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_labels_id_seq', 1, false);


--
-- Name: flows_flow_template_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_template_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_ticketer_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_ticketer_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_topic_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_topic_dependencies_id_seq', 1, false);


--
-- Name: flows_flow_user_dependencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flow_user_dependencies_id_seq', 1, false);


--
-- Name: flows_flowcategorycount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowcategorycount_id_seq', 1, false);


--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowlabel_id_seq', 1, false);


--
-- Name: flows_flownodecount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flownodecount_id_seq', 1, false);


--
-- Name: flows_flowpathcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowpathcount_id_seq', 1, false);


--
-- Name: flows_flowrevision_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowrevision_id_seq', 3, true);


--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowrun_id_seq', 1, false);


--
-- Name: flows_flowruncount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowruncount_id_seq', 1, false);


--
-- Name: flows_flowsession_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowsession_id_seq', 1, false);


--
-- Name: flows_flowstart_connections_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowstart_connections_id_seq', 1, false);


--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowstart_contacts_id_seq', 1, false);


--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowstart_groups_id_seq', 1, false);


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowstart_id_seq', 1, false);


--
-- Name: flows_flowstartcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.flows_flowstartcount_id_seq', 1, false);


--
-- Name: globals_global_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.globals_global_id_seq', 1, false);


--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.locations_adminboundary_id_seq', 1, false);


--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.locations_boundaryalias_id_seq', 1, false);


--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_broadcast_contacts_id_seq', 1, false);


--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_broadcast_groups_id_seq', 1, false);


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_broadcast_id_seq', 1, false);


--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_broadcast_urns_id_seq', 1, false);


--
-- Name: msgs_broadcastmsgcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_broadcastmsgcount_id_seq', 1, false);


--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_exportmessagestask_groups_id_seq', 1, false);


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_exportmessagestask_id_seq', 1, false);


--
-- Name: msgs_label_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_label_id_seq', 1, false);


--
-- Name: msgs_labelcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_labelcount_id_seq', 1, false);


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_msg_id_seq', 1, false);


--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_msg_labels_id_seq', 1, false);


--
-- Name: msgs_systemlabelcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.msgs_systemlabelcount_id_seq', 1, false);


--
-- Name: notifications_incident_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.notifications_incident_id_seq', 1, false);


--
-- Name: notifications_notification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.notifications_notification_id_seq', 1, false);


--
-- Name: notifications_notificationcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.notifications_notificationcount_id_seq', 1, false);


--
-- Name: orgs_backuptoken_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_backuptoken_id_seq', 1, false);


--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_creditalert_id_seq', 1, false);


--
-- Name: orgs_debit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_debit_id_seq', 1, false);


--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_invitation_id_seq', 1, false);


--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_administrators_id_seq', 1, true);


--
-- Name: orgs_org_agents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_agents_id_seq', 1, false);


--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_editors_id_seq', 1, false);


--
-- Name: orgs_org_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_id_seq', 1, true);


--
-- Name: orgs_org_surveyors_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_surveyors_id_seq', 1, false);


--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_org_viewers_id_seq', 1, false);


--
-- Name: orgs_orgactivity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_orgactivity_id_seq', 1, false);


--
-- Name: orgs_orgmembership_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_orgmembership_id_seq', 1, true);


--
-- Name: orgs_topup_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_topup_id_seq', 1, true);


--
-- Name: orgs_topupcredits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_topupcredits_id_seq', 1, false);


--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.orgs_usersettings_id_seq', 1, true);


--
-- Name: policies_consent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.policies_consent_id_seq', 1, false);


--
-- Name: policies_policy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.policies_policy_id_seq', 1, false);


--
-- Name: public_lead_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.public_lead_id_seq', 1, false);


--
-- Name: public_video_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.public_video_id_seq', 1, false);


--
-- Name: request_logs_httplog_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.request_logs_httplog_id_seq', 1, false);


--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.schedules_schedule_id_seq', 1, false);


--
-- Name: templates_template_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.templates_template_id_seq', 1, false);


--
-- Name: templates_templatetranslation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.templates_templatetranslation_id_seq', 1, false);


--
-- Name: tickets_team_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_team_id_seq', 1, false);


--
-- Name: tickets_team_topics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_team_topics_id_seq', 1, false);


--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticket_id_seq', 1, false);


--
-- Name: tickets_ticketcount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticketcount_id_seq', 1, false);


--
-- Name: tickets_ticketdailycount_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticketdailycount_id_seq', 1, false);


--
-- Name: tickets_ticketdailytiming_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticketdailytiming_id_seq', 1, false);


--
-- Name: tickets_ticketer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticketer_id_seq', 1, true);


--
-- Name: tickets_ticketevent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_ticketevent_id_seq', 1, false);


--
-- Name: tickets_topic_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.tickets_topic_id_seq', 1, true);


--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.triggers_trigger_contacts_id_seq', 1, false);


--
-- Name: triggers_trigger_exclude_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.triggers_trigger_exclude_groups_id_seq', 1, false);


--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.triggers_trigger_groups_id_seq', 1, false);


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.triggers_trigger_id_seq', 1, true);


--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.users_failedlogin_id_seq', 5, true);


--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.users_passwordhistory_id_seq', 1, false);


--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE SET; Schema: public; Owner: flowartisan
--

SELECT pg_catalog.setval('public.users_recoverytoken_id_seq', 1, false);


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_pkey PRIMARY KEY (id);


--
-- Name: api_apitoken api_apitoken_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_apitoken
    ADD CONSTRAINT api_apitoken_pkey PRIMARY KEY (key);


--
-- Name: api_resthook api_resthook_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthook
    ADD CONSTRAINT api_resthook_pkey PRIMARY KEY (id);


--
-- Name: api_resthooksubscriber api_resthooksubscriber_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_pkey PRIMARY KEY (id);


--
-- Name: api_webhookevent api_webhookevent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_webhookevent
    ADD CONSTRAINT api_webhookevent_pkey PRIMARY KEY (id);


--
-- Name: apks_apk apks_apk_apk_type_version_pack_e0dd7b4c_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.apks_apk
    ADD CONSTRAINT apks_apk_apk_type_version_pack_e0dd7b4c_uniq UNIQUE (apk_type, version, pack);


--
-- Name: apks_apk apks_apk_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.apks_apk
    ADD CONSTRAINT apks_apk_pkey PRIMARY KEY (id);


--
-- Name: archives_archive archives_archive_org_id_archive_type_star_e404e29b_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.archives_archive
    ADD CONSTRAINT archives_archive_org_id_archive_type_star_e404e29b_uniq UNIQUE (org_id, archive_type, start_date, period);


--
-- Name: archives_archive archives_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.archives_archive
    ADD CONSTRAINT archives_archive_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: authtoken_token authtoken_token_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_pkey PRIMARY KEY (key);


--
-- Name: authtoken_token authtoken_token_user_id_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_key UNIQUE (user_id);


--
-- Name: campaigns_campaign campaigns_campaign_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaign campaigns_campaign_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_uuid_key UNIQUE (uuid);


--
-- Name: campaigns_campaignevent campaigns_campaignevent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaignevent campaigns_campaignevent_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_uuid_key UNIQUE (uuid);


--
-- Name: campaigns_eventfire campaigns_eventfire_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_pkey PRIMARY KEY (id);


--
-- Name: channels_alert channels_alert_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert
    ADD CONSTRAINT channels_alert_pkey PRIMARY KEY (id);


--
-- Name: channels_channel channels_channel_claim_code_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_claim_code_key UNIQUE (claim_code);


--
-- Name: channels_channel channels_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_pkey PRIMARY KEY (id);


--
-- Name: channels_channel channels_channel_secret_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_secret_key UNIQUE (secret);


--
-- Name: channels_channel channels_channel_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_uuid_key UNIQUE (uuid);


--
-- Name: channels_channelconnection channels_channelconnection_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection
    ADD CONSTRAINT channels_channelconnection_pkey PRIMARY KEY (id);


--
-- Name: channels_channelcount channels_channelcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelcount
    ADD CONSTRAINT channels_channelcount_pkey PRIMARY KEY (id);


--
-- Name: channels_channelevent channels_channelevent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent
    ADD CONSTRAINT channels_channelevent_pkey PRIMARY KEY (id);


--
-- Name: channels_channellog channels_channellog_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channellog
    ADD CONSTRAINT channels_channellog_pkey PRIMARY KEY (id);


--
-- Name: channels_syncevent channels_syncevent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_syncevent
    ADD CONSTRAINT channels_syncevent_pkey PRIMARY KEY (id);


--
-- Name: classifiers_classifier classifiers_classifier_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier
    ADD CONSTRAINT classifiers_classifier_pkey PRIMARY KEY (id);


--
-- Name: classifiers_classifier classifiers_classifier_uuid_ee46e09f_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier
    ADD CONSTRAINT classifiers_classifier_uuid_ee46e09f_uniq UNIQUE (uuid);


--
-- Name: classifiers_intent classifiers_intent_classifier_id_external_id_7b4d9a43_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_intent
    ADD CONSTRAINT classifiers_intent_classifier_id_external_id_7b4d9a43_uniq UNIQUE (classifier_id, external_id);


--
-- Name: classifiers_intent classifiers_intent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_intent
    ADD CONSTRAINT classifiers_intent_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact contacts_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact contacts_contact_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactfield contacts_contactfield_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactfield contacts_contactfield_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactgroup_contacts contacts_contactgroup_co_contactgroup_id_contact__0f909f73_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_co_contactgroup_id_contact__0f909f73_uniq UNIQUE (contactgroup_id, contact_id);


--
-- Name: contacts_contactgroup_contacts contacts_contactgroup_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup contacts_contactgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_query_fields contacts_contactgroup_qu_contactgroup_id_contactf_642b9244_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_qu_contactgroup_id_contactf_642b9244_uniq UNIQUE (contactgroup_id, contactfield_id);


--
-- Name: contacts_contactgroup_query_fields contacts_contactgroup_query_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_fields_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup contacts_contactgroup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactgroupcount contacts_contactgroupcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroupcount
    ADD CONSTRAINT contacts_contactgroupcount_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactimport contacts_contactimport_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport
    ADD CONSTRAINT contacts_contactimport_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactimportbatch contacts_contactimportbatch_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimportbatch
    ADD CONSTRAINT contacts_contactimportbatch_pkey PRIMARY KEY (id);


--
-- Name: contacts_contacturn contacts_contacturn_identity_org_id_70c84094_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_identity_org_id_70c84094_uniq UNIQUE (identity, org_id);


--
-- Name: contacts_contacturn contacts_contacturn_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_pkey PRIMARY KEY (id);


--
-- Name: contacts_exportcontactstask_group_memberships contacts_exportcontactst_exportcontactstask_id_co_36ae4836_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask_group_memberships
    ADD CONSTRAINT contacts_exportcontactst_exportcontactstask_id_co_36ae4836_uniq UNIQUE (exportcontactstask_id, contactgroup_id);


--
-- Name: contacts_exportcontactstask_group_memberships contacts_exportcontactstask_group_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask_group_memberships
    ADD CONSTRAINT contacts_exportcontactstask_group_memberships_pkey PRIMARY KEY (id);


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_pkey PRIMARY KEY (id);


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_uuid_key UNIQUE (uuid);


--
-- Name: csv_imports_importtask csv_imports_importtask_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: django_site django_site_domain_a2e37b91_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_site
    ADD CONSTRAINT django_site_domain_a2e37b91_uniq UNIQUE (domain);


--
-- Name: django_site django_site_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.django_site
    ADD CONSTRAINT django_site_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresultst_exportflowresultstask_id_4e70a5c5_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultst_exportflowresultstask_id_4e70a5c5_uniq UNIQUE (exportflowresultstask_id, flow_id);


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresultstask_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_flows_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_uuid_key UNIQUE (uuid);


--
-- Name: flows_flow_channel_dependencies flows_flow_channel_depen_flow_id_channel_id_41906974_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_channel_dependencies
    ADD CONSTRAINT flows_flow_channel_depen_flow_id_channel_id_41906974_uniq UNIQUE (flow_id, channel_id);


--
-- Name: flows_flow_channel_dependencies flows_flow_channel_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_channel_dependencies
    ADD CONSTRAINT flows_flow_channel_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_classifier_dependencies flows_flow_classifier_de_flow_id_classifier_id_dcbae13a_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_classifier_dependencies
    ADD CONSTRAINT flows_flow_classifier_de_flow_id_classifier_id_dcbae13a_uniq UNIQUE (flow_id, classifier_id);


--
-- Name: flows_flow_classifier_dependencies flows_flow_classifier_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_classifier_dependencies
    ADD CONSTRAINT flows_flow_classifier_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_field_dependencies flows_flow_field_depende_flow_id_contactfield_id_4fecad40_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_field_dependencies
    ADD CONSTRAINT flows_flow_field_depende_flow_id_contactfield_id_4fecad40_uniq UNIQUE (flow_id, contactfield_id);


--
-- Name: flows_flow_field_dependencies flows_flow_field_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_field_dependencies
    ADD CONSTRAINT flows_flow_field_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_flow_dependencies flows_flow_flow_dependen_from_flow_id_to_flow_id_9eb32a37_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_flow_dependencies
    ADD CONSTRAINT flows_flow_flow_dependen_from_flow_id_to_flow_id_9eb32a37_uniq UNIQUE (from_flow_id, to_flow_id);


--
-- Name: flows_flow_flow_dependencies flows_flow_flow_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_flow_dependencies
    ADD CONSTRAINT flows_flow_flow_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_global_dependencies flows_flow_global_dependencies_flow_id_global_id_2a4f4f8e_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_global_dependencies
    ADD CONSTRAINT flows_flow_global_dependencies_flow_id_global_id_2a4f4f8e_uniq UNIQUE (flow_id, global_id);


--
-- Name: flows_flow_global_dependencies flows_flow_global_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_global_dependencies
    ADD CONSTRAINT flows_flow_global_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_group_dependencies flows_flow_group_depende_flow_id_contactgroup_id_a874ba76_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_group_dependencies
    ADD CONSTRAINT flows_flow_group_depende_flow_id_contactgroup_id_a874ba76_uniq UNIQUE (flow_id, contactgroup_id);


--
-- Name: flows_flow_group_dependencies flows_flow_group_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_group_dependencies
    ADD CONSTRAINT flows_flow_group_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_label_dependencies flows_flow_label_dependencies_flow_id_label_id_6f3e9491_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_label_dependencies
    ADD CONSTRAINT flows_flow_label_dependencies_flow_id_label_id_6f3e9491_uniq UNIQUE (flow_id, label_id);


--
-- Name: flows_flow_label_dependencies flows_flow_label_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_label_dependencies
    ADD CONSTRAINT flows_flow_label_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_labels flows_flow_labels_flow_id_flowlabel_id_99ec8abf_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_flowlabel_id_99ec8abf_uniq UNIQUE (flow_id, flowlabel_id);


--
-- Name: flows_flow_labels flows_flow_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_pkey PRIMARY KEY (id);


--
-- Name: flows_flow flows_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_template_dependencies flows_flow_template_depe_flow_id_template_id_f042658a_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_template_dependencies
    ADD CONSTRAINT flows_flow_template_depe_flow_id_template_id_f042658a_uniq UNIQUE (flow_id, template_id);


--
-- Name: flows_flow_template_dependencies flows_flow_template_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_template_dependencies
    ADD CONSTRAINT flows_flow_template_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_ticketer_dependencies flows_flow_ticketer_depe_flow_id_ticketer_id_3b564da9_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_ticketer_dependencies
    ADD CONSTRAINT flows_flow_ticketer_depe_flow_id_ticketer_id_3b564da9_uniq UNIQUE (flow_id, ticketer_id);


--
-- Name: flows_flow_ticketer_dependencies flows_flow_ticketer_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_ticketer_dependencies
    ADD CONSTRAINT flows_flow_ticketer_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_topic_dependencies flows_flow_topic_dependencies_flow_id_topic_id_77a28a41_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_topic_dependencies
    ADD CONSTRAINT flows_flow_topic_dependencies_flow_id_topic_id_77a28a41_uniq UNIQUE (flow_id, topic_id);


--
-- Name: flows_flow_topic_dependencies flows_flow_topic_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_topic_dependencies
    ADD CONSTRAINT flows_flow_topic_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_user_dependencies flows_flow_user_dependencies_flow_id_user_id_02d2213e_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_user_dependencies
    ADD CONSTRAINT flows_flow_user_dependencies_flow_id_user_id_02d2213e_uniq UNIQUE (flow_id, user_id);


--
-- Name: flows_flow_user_dependencies flows_flow_user_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_user_dependencies
    ADD CONSTRAINT flows_flow_user_dependencies_pkey PRIMARY KEY (id);


--
-- Name: flows_flow flows_flow_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_uuid_key UNIQUE (uuid);


--
-- Name: flows_flowcategorycount flows_flowcategorycount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowcategorycount
    ADD CONSTRAINT flows_flowcategorycount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowlabel flows_flowlabel_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_pkey PRIMARY KEY (id);


--
-- Name: flows_flowlabel flows_flowlabel_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_uuid_key UNIQUE (uuid);


--
-- Name: flows_flownodecount flows_flownodecount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flownodecount
    ADD CONSTRAINT flows_flownodecount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowpathcount flows_flowpathcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowpathcount
    ADD CONSTRAINT flows_flowpathcount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrevision flows_flowrevision_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun flows_flowrun_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun flows_flowrun_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_uuid_key UNIQUE (uuid);


--
-- Name: flows_flowruncount flows_flowruncount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowruncount
    ADD CONSTRAINT flows_flowruncount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowsession flows_flowsession_connection_id_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_connection_id_key UNIQUE (connection_id);


--
-- Name: flows_flowsession flows_flowsession_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_pkey PRIMARY KEY (id);


--
-- Name: flows_flowsession flows_flowsession_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_uuid_key UNIQUE (uuid);


--
-- Name: flows_flowstart_connections flows_flowstart_connecti_flowstart_id_channelconn_8b0d0f44_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_connections
    ADD CONSTRAINT flows_flowstart_connecti_flowstart_id_channelconn_8b0d0f44_uniq UNIQUE (flowstart_id, channelconnection_id);


--
-- Name: flows_flowstart_connections flows_flowstart_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_connections
    ADD CONSTRAINT flows_flowstart_connections_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_contacts flows_flowstart_contacts_flowstart_id_contact_id_88b65412_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_flowstart_id_contact_id_88b65412_uniq UNIQUE (flowstart_id, contact_id);


--
-- Name: flows_flowstart_contacts flows_flowstart_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_groups flows_flowstart_groups_flowstart_id_contactgrou_fc0b5f4f_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_flowstart_id_contactgrou_fc0b5f4f_uniq UNIQUE (flowstart_id, contactgroup_id);


--
-- Name: flows_flowstart_groups flows_flowstart_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart flows_flowstart_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart flows_flowstart_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_uuid_key UNIQUE (uuid);


--
-- Name: flows_flowstartcount flows_flowstartcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstartcount
    ADD CONSTRAINT flows_flowstartcount_pkey PRIMARY KEY (id);


--
-- Name: globals_global globals_global_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global
    ADD CONSTRAINT globals_global_pkey PRIMARY KEY (id);


--
-- Name: globals_global globals_global_uuid_e43a3dd2_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global
    ADD CONSTRAINT globals_global_uuid_e43a3dd2_uniq UNIQUE (uuid);


--
-- Name: locations_adminboundary locations_adminboundary_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_osm_id_key UNIQUE (osm_id);


--
-- Name: locations_adminboundary locations_adminboundary_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_pkey PRIMARY KEY (id);


--
-- Name: locations_boundaryalias locations_boundaryalias_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_contacts msgs_broadcast_contacts_broadcast_id_contact_id_85ec2380_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_broadcast_id_contact_id_85ec2380_uniq UNIQUE (broadcast_id, contact_id);


--
-- Name: msgs_broadcast_contacts msgs_broadcast_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_groups msgs_broadcast_groups_broadcast_id_contactgrou_bc725cf0_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_broadcast_id_contactgrou_bc725cf0_uniq UNIQUE (broadcast_id, contactgroup_id);


--
-- Name: msgs_broadcast_groups msgs_broadcast_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast msgs_broadcast_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast msgs_broadcast_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_key UNIQUE (schedule_id);


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_broadcast_id_contacturn_id_5fe7764f_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_contacturn_id_5fe7764f_uniq UNIQUE (broadcast_id, contacturn_id);


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcastmsgcount msgs_broadcastmsgcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcastmsgcount
    ADD CONSTRAINT msgs_broadcastmsgcount_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagestask__exportmessagestask_id_co_d2d2009a_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask__exportmessagestask_id_co_d2d2009a_uniq UNIQUE (exportmessagestask_id, contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagestask_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_uuid_key UNIQUE (uuid);


--
-- Name: msgs_label msgs_label_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_pkey PRIMARY KEY (id);


--
-- Name: msgs_label msgs_label_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_uuid_key UNIQUE (uuid);


--
-- Name: msgs_labelcount msgs_labelcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_labelcount
    ADD CONSTRAINT msgs_labelcount_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg_labels msgs_msg_labels_msg_id_label_id_98060205_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_label_id_98060205_uniq UNIQUE (msg_id, label_id);


--
-- Name: msgs_msg_labels msgs_msg_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg msgs_msg_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_pkey PRIMARY KEY (id);


--
-- Name: msgs_systemlabelcount msgs_systemlabelcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_systemlabelcount
    ADD CONSTRAINT msgs_systemlabelcount_pkey PRIMARY KEY (id);


--
-- Name: notifications_incident notifications_incident_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_incident
    ADD CONSTRAINT notifications_incident_pkey PRIMARY KEY (id);


--
-- Name: notifications_notification notifications_notification_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notification_pkey PRIMARY KEY (id);


--
-- Name: notifications_notificationcount notifications_notificationcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notificationcount
    ADD CONSTRAINT notifications_notificationcount_pkey PRIMARY KEY (id);


--
-- Name: orgs_backuptoken orgs_backuptoken_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_backuptoken
    ADD CONSTRAINT orgs_backuptoken_pkey PRIMARY KEY (id);


--
-- Name: orgs_backuptoken orgs_backuptoken_token_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_backuptoken
    ADD CONSTRAINT orgs_backuptoken_token_key UNIQUE (token);


--
-- Name: orgs_creditalert orgs_creditalert_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_pkey PRIMARY KEY (id);


--
-- Name: orgs_debit orgs_debit_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_debit
    ADD CONSTRAINT orgs_debit_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation orgs_invitation_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation
    ADD CONSTRAINT orgs_invitation_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation orgs_invitation_secret_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation
    ADD CONSTRAINT orgs_invitation_secret_key UNIQUE (secret);


--
-- Name: orgs_org_administrators orgs_org_administrators_org_id_user_id_c6cb5bee_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_user_id_c6cb5bee_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_administrators orgs_org_administrators_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_agents orgs_org_agents_org_id_user_id_5939c8e7_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_agents
    ADD CONSTRAINT orgs_org_agents_org_id_user_id_5939c8e7_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_agents orgs_org_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_agents
    ADD CONSTRAINT orgs_org_agents_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_editors orgs_org_editors_org_id_user_id_635dc129_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_user_id_635dc129_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_editors orgs_org_editors_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org orgs_org_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_pkey PRIMARY KEY (id);


--
-- Name: orgs_org orgs_org_slug_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_slug_key UNIQUE (slug);


--
-- Name: orgs_org_surveyors orgs_org_surveyors_org_id_user_id_f78ff12f_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_org_id_user_id_f78ff12f_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_surveyors orgs_org_surveyors_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org orgs_org_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_uuid_key UNIQUE (uuid);


--
-- Name: orgs_org_viewers orgs_org_viewers_org_id_user_id_451e0d91_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_user_id_451e0d91_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_viewers orgs_org_viewers_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_pkey PRIMARY KEY (id);


--
-- Name: orgs_orgactivity orgs_orgactivity_org_id_day_081fd0e8_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgactivity
    ADD CONSTRAINT orgs_orgactivity_org_id_day_081fd0e8_uniq UNIQUE (org_id, day);


--
-- Name: orgs_orgactivity orgs_orgactivity_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgactivity
    ADD CONSTRAINT orgs_orgactivity_pkey PRIMARY KEY (id);


--
-- Name: orgs_orgmembership orgs_orgmembership_org_id_user_id_3d615bc7_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgmembership
    ADD CONSTRAINT orgs_orgmembership_org_id_user_id_3d615bc7_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_orgmembership orgs_orgmembership_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgmembership
    ADD CONSTRAINT orgs_orgmembership_pkey PRIMARY KEY (id);


--
-- Name: orgs_topup orgs_topup_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topup
    ADD CONSTRAINT orgs_topup_pkey PRIMARY KEY (id);


--
-- Name: orgs_topupcredits orgs_topupcredits_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topupcredits
    ADD CONSTRAINT orgs_topupcredits_pkey PRIMARY KEY (id);


--
-- Name: orgs_usersettings orgs_usersettings_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_pkey PRIMARY KEY (id);


--
-- Name: policies_consent policies_consent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_consent
    ADD CONSTRAINT policies_consent_pkey PRIMARY KEY (id);


--
-- Name: policies_policy policies_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_policy
    ADD CONSTRAINT policies_policy_pkey PRIMARY KEY (id);


--
-- Name: public_lead public_lead_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_lead
    ADD CONSTRAINT public_lead_pkey PRIMARY KEY (id);


--
-- Name: public_video public_video_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_video
    ADD CONSTRAINT public_video_pkey PRIMARY KEY (id);


--
-- Name: request_logs_httplog request_logs_httplog_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_pkey PRIMARY KEY (id);


--
-- Name: schedules_schedule schedules_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.schedules_schedule
    ADD CONSTRAINT schedules_schedule_pkey PRIMARY KEY (id);


--
-- Name: templates_template templates_template_org_id_name_4fdfeae4_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_template
    ADD CONSTRAINT templates_template_org_id_name_4fdfeae4_uniq UNIQUE (org_id, name);


--
-- Name: templates_template templates_template_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_template
    ADD CONSTRAINT templates_template_pkey PRIMARY KEY (id);


--
-- Name: templates_templatetranslation templates_templatetranslation_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_templatetranslation
    ADD CONSTRAINT templates_templatetranslation_pkey PRIMARY KEY (id);


--
-- Name: tickets_team tickets_team_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team
    ADD CONSTRAINT tickets_team_pkey PRIMARY KEY (id);


--
-- Name: tickets_team_topics tickets_team_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team_topics
    ADD CONSTRAINT tickets_team_topics_pkey PRIMARY KEY (id);


--
-- Name: tickets_team_topics tickets_team_topics_team_id_topic_id_cbcc8f8e_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team_topics
    ADD CONSTRAINT tickets_team_topics_team_id_topic_id_cbcc8f8e_uniq UNIQUE (team_id, topic_id);


--
-- Name: tickets_team tickets_team_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team
    ADD CONSTRAINT tickets_team_uuid_key UNIQUE (uuid);


--
-- Name: tickets_ticket tickets_ticket_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_pkey PRIMARY KEY (id);


--
-- Name: tickets_ticket tickets_ticket_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_uuid_key UNIQUE (uuid);


--
-- Name: tickets_ticketcount tickets_ticketcount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketcount
    ADD CONSTRAINT tickets_ticketcount_pkey PRIMARY KEY (id);


--
-- Name: tickets_ticketdailycount tickets_ticketdailycount_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketdailycount
    ADD CONSTRAINT tickets_ticketdailycount_pkey PRIMARY KEY (id);


--
-- Name: tickets_ticketdailytiming tickets_ticketdailytiming_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketdailytiming
    ADD CONSTRAINT tickets_ticketdailytiming_pkey PRIMARY KEY (id);


--
-- Name: tickets_ticketer tickets_ticketer_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer
    ADD CONSTRAINT tickets_ticketer_pkey PRIMARY KEY (id);


--
-- Name: tickets_ticketer tickets_ticketer_uuid_78ff1b2a_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer
    ADD CONSTRAINT tickets_ticketer_uuid_78ff1b2a_uniq UNIQUE (uuid);


--
-- Name: tickets_ticketevent tickets_ticketevent_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_pkey PRIMARY KEY (id);


--
-- Name: tickets_topic tickets_topic_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic
    ADD CONSTRAINT tickets_topic_pkey PRIMARY KEY (id);


--
-- Name: tickets_topic tickets_topic_uuid_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic
    ADD CONSTRAINT tickets_topic_uuid_key UNIQUE (uuid);


--
-- Name: triggers_trigger_contacts triggers_trigger_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts triggers_trigger_contacts_trigger_id_contact_id_a5309237_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_trigger_id_contact_id_a5309237_uniq UNIQUE (trigger_id, contact_id);


--
-- Name: triggers_trigger_exclude_groups triggers_trigger_exclude_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_exclude_groups
    ADD CONSTRAINT triggers_trigger_exclude_groups_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_exclude_groups triggers_trigger_exclude_trigger_id_contactgroup__8d6addbc_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_exclude_groups
    ADD CONSTRAINT triggers_trigger_exclude_trigger_id_contactgroup__8d6addbc_uniq UNIQUE (trigger_id, contactgroup_id);


--
-- Name: triggers_trigger_groups triggers_trigger_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_groups triggers_trigger_groups_trigger_id_contactgroup__cf0ee28d_uniq; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_trigger_id_contactgroup__cf0ee28d_uniq UNIQUE (trigger_id, contactgroup_id);


--
-- Name: triggers_trigger triggers_trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger triggers_trigger_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_key UNIQUE (schedule_id);


--
-- Name: users_failedlogin users_failedlogin_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_failedlogin
    ADD CONSTRAINT users_failedlogin_pkey PRIMARY KEY (id);


--
-- Name: users_passwordhistory users_passwordhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken users_recoverytoken_pkey; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken users_recoverytoken_token_key; Type: CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_token_key UNIQUE (token);


--
-- Name: airtime_airtimetransfer_contact_id_e90a2275; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX airtime_airtimetransfer_contact_id_e90a2275 ON public.airtime_airtimetransfer USING btree (contact_id);


--
-- Name: airtime_airtimetransfer_org_id_3eef5867; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX airtime_airtimetransfer_org_id_3eef5867 ON public.airtime_airtimetransfer USING btree (org_id);


--
-- Name: api_apitoken_key_e6fcf24a_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_apitoken_key_e6fcf24a_like ON public.api_apitoken USING btree (key varchar_pattern_ops);


--
-- Name: api_apitoken_org_id_b1411661; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_apitoken_org_id_b1411661 ON public.api_apitoken USING btree (org_id);


--
-- Name: api_apitoken_role_id_391adbf5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_apitoken_role_id_391adbf5 ON public.api_apitoken USING btree (role_id);


--
-- Name: api_apitoken_user_id_9cffaf33; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_apitoken_user_id_9cffaf33 ON public.api_apitoken USING btree (user_id);


--
-- Name: api_resthook_created_by_id_26c82721; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthook_created_by_id_26c82721 ON public.api_resthook USING btree (created_by_id);


--
-- Name: api_resthook_modified_by_id_d5b8e394; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthook_modified_by_id_d5b8e394 ON public.api_resthook USING btree (modified_by_id);


--
-- Name: api_resthook_org_id_3ac815fe; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthook_org_id_3ac815fe ON public.api_resthook USING btree (org_id);


--
-- Name: api_resthook_slug_19d1d7bf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthook_slug_19d1d7bf ON public.api_resthook USING btree (slug);


--
-- Name: api_resthook_slug_19d1d7bf_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthook_slug_19d1d7bf_like ON public.api_resthook USING btree (slug varchar_pattern_ops);


--
-- Name: api_resthooksubscriber_created_by_id_ff38300d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthooksubscriber_created_by_id_ff38300d ON public.api_resthooksubscriber USING btree (created_by_id);


--
-- Name: api_resthooksubscriber_modified_by_id_0e996ea4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthooksubscriber_modified_by_id_0e996ea4 ON public.api_resthooksubscriber USING btree (modified_by_id);


--
-- Name: api_resthooksubscriber_resthook_id_59cd8bc3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_resthooksubscriber_resthook_id_59cd8bc3 ON public.api_resthooksubscriber USING btree (resthook_id);


--
-- Name: api_webhookevent_org_id_2c305947; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_webhookevent_org_id_2c305947 ON public.api_webhookevent USING btree (org_id);


--
-- Name: api_webhookevent_resthook_id_d2f95048; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX api_webhookevent_resthook_id_d2f95048 ON public.api_webhookevent USING btree (resthook_id);


--
-- Name: archives_archive_org_id_d19c8f63; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX archives_archive_org_id_d19c8f63 ON public.archives_archive USING btree (org_id);


--
-- Name: archives_archive_rollup_id_88538d7b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX archives_archive_rollup_id_88538d7b ON public.archives_archive USING btree (rollup_id);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: authtoken_token_key_10f0b77e_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX authtoken_token_key_10f0b77e_like ON public.authtoken_token USING btree (key varchar_pattern_ops);


--
-- Name: campaigns_campaign_created_by_id_11fada74; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaign_created_by_id_11fada74 ON public.campaigns_campaign USING btree (created_by_id);


--
-- Name: campaigns_campaign_group_id_c1118360; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaign_group_id_c1118360 ON public.campaigns_campaign USING btree (group_id);


--
-- Name: campaigns_campaign_modified_by_id_d578b992; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaign_modified_by_id_d578b992 ON public.campaigns_campaign USING btree (modified_by_id);


--
-- Name: campaigns_campaign_org_id_ac7ac4ee; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaign_org_id_ac7ac4ee ON public.campaigns_campaign USING btree (org_id);


--
-- Name: campaigns_campaignevent_campaign_id_7752d8e7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaignevent_campaign_id_7752d8e7 ON public.campaigns_campaignevent USING btree (campaign_id);


--
-- Name: campaigns_campaignevent_created_by_id_7755844d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaignevent_created_by_id_7755844d ON public.campaigns_campaignevent USING btree (created_by_id);


--
-- Name: campaigns_campaignevent_flow_id_7a962066; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaignevent_flow_id_7a962066 ON public.campaigns_campaignevent USING btree (flow_id);


--
-- Name: campaigns_campaignevent_modified_by_id_9645785d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaignevent_modified_by_id_9645785d ON public.campaigns_campaignevent USING btree (modified_by_id);


--
-- Name: campaigns_campaignevent_relative_to_id_f8130023; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_campaignevent_relative_to_id_f8130023 ON public.campaigns_campaignevent USING btree (relative_to_id);


--
-- Name: campaigns_eventfire_contact_id_7d58f0a5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_eventfire_contact_id_7d58f0a5 ON public.campaigns_eventfire USING btree (contact_id);


--
-- Name: campaigns_eventfire_event_id_f5396422; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_eventfire_event_id_f5396422 ON public.campaigns_eventfire USING btree (event_id);


--
-- Name: campaigns_eventfire_fired_not_null_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX campaigns_eventfire_fired_not_null_idx ON public.campaigns_eventfire USING btree (fired) WHERE (fired IS NOT NULL);


--
-- Name: campaigns_eventfire_unfired_unique; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX campaigns_eventfire_unfired_unique ON public.campaigns_eventfire USING btree (event_id, contact_id, ((fired IS NULL))) WHERE (fired IS NULL);


--
-- Name: channelconnection_ivr_to_retry; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channelconnection_ivr_to_retry ON public.channels_channelconnection USING btree (next_attempt) WHERE (((connection_type)::text = 'V'::text) AND (next_attempt IS NOT NULL) AND ((status)::text = ANY ((ARRAY['Q'::character varying, 'E'::character varying])::text[])));


--
-- Name: channels_alert_channel_id_1344ae59; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_alert_channel_id_1344ae59 ON public.channels_alert USING btree (channel_id);


--
-- Name: channels_alert_created_by_id_1b7c1310; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_alert_created_by_id_1b7c1310 ON public.channels_alert USING btree (created_by_id);


--
-- Name: channels_alert_modified_by_id_e2555348; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_alert_modified_by_id_e2555348 ON public.channels_alert USING btree (modified_by_id);


--
-- Name: channels_alert_sync_event_id_c866791c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_alert_sync_event_id_c866791c ON public.channels_alert USING btree (sync_event_id);


--
-- Name: channels_channel_android_last_seen_active; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_android_last_seen_active ON public.channels_channel USING btree (last_seen) WHERE (((channel_type)::text = 'A'::text) AND (is_active = true));


--
-- Name: channels_channel_claim_code_13b82678_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_claim_code_13b82678_like ON public.channels_channel USING btree (claim_code varchar_pattern_ops);


--
-- Name: channels_channel_created_by_id_8141adf4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_created_by_id_8141adf4 ON public.channels_channel USING btree (created_by_id);


--
-- Name: channels_channel_modified_by_id_af6bcc5e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_modified_by_id_af6bcc5e ON public.channels_channel USING btree (modified_by_id);


--
-- Name: channels_channel_org_id_fd34a95a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_org_id_fd34a95a ON public.channels_channel USING btree (org_id);


--
-- Name: channels_channel_parent_id_6e9cc8f5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_parent_id_6e9cc8f5 ON public.channels_channel USING btree (parent_id);


--
-- Name: channels_channel_secret_7f9a562d_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_secret_7f9a562d_like ON public.channels_channel USING btree (secret varchar_pattern_ops);


--
-- Name: channels_channel_uuid_6008b898_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channel_uuid_6008b898_like ON public.channels_channel USING btree (uuid varchar_pattern_ops);


--
-- Name: channels_channelconnection_channel_id_d69daad3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelconnection_channel_id_d69daad3 ON public.channels_channelconnection USING btree (channel_id);


--
-- Name: channels_channelconnection_contact_id_fe6e9aa5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelconnection_contact_id_fe6e9aa5 ON public.channels_channelconnection USING btree (contact_id);


--
-- Name: channels_channelconnection_contact_urn_id_b28c1c6d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelconnection_contact_urn_id_b28c1c6d ON public.channels_channelconnection USING btree (contact_urn_id);


--
-- Name: channels_channelconnection_org_id_585658cf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelconnection_org_id_585658cf ON public.channels_channelconnection USING btree (org_id);


--
-- Name: channels_channelcount_channel_id_b996d6ab; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelcount_channel_id_b996d6ab ON public.channels_channelcount USING btree (channel_id);


--
-- Name: channels_channelcount_channel_id_count_type_day_361bd585_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelcount_channel_id_count_type_day_361bd585_idx ON public.channels_channelcount USING btree (channel_id, count_type, day);


--
-- Name: channels_channelcount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelcount_unsquashed ON public.channels_channelcount USING btree (channel_id, count_type, day) WHERE (NOT is_squashed);


--
-- Name: channels_channelevent_channel_id_ba42cee7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelevent_channel_id_ba42cee7 ON public.channels_channelevent USING btree (channel_id);


--
-- Name: channels_channelevent_contact_id_054a8a49; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelevent_contact_id_054a8a49 ON public.channels_channelevent USING btree (contact_id);


--
-- Name: channels_channelevent_contact_urn_id_0d28570b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelevent_contact_urn_id_0d28570b ON public.channels_channelevent USING btree (contact_urn_id);


--
-- Name: channels_channelevent_org_id_4d7fff63; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channelevent_org_id_4d7fff63 ON public.channels_channelevent USING btree (org_id);


--
-- Name: channels_channellog_channel_created_on; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channellog_channel_created_on ON public.channels_channellog USING btree (channel_id, created_on DESC);


--
-- Name: channels_channellog_channel_id_567d1602; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channellog_channel_id_567d1602 ON public.channels_channellog USING btree (channel_id);


--
-- Name: channels_channellog_connection_id_2609da75; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channellog_connection_id_2609da75 ON public.channels_channellog USING btree (connection_id);


--
-- Name: channels_channellog_msg_id_e40e6612; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_channellog_msg_id_e40e6612 ON public.channels_channellog USING btree (msg_id);


--
-- Name: channels_log_error_created; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_log_error_created ON public.channels_channellog USING btree (channel_id, is_error, created_on DESC) WHERE is_error;


--
-- Name: channels_syncevent_channel_id_4b72a0f3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_syncevent_channel_id_4b72a0f3 ON public.channels_syncevent USING btree (channel_id);


--
-- Name: channels_syncevent_created_by_id_1f26df72; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_syncevent_created_by_id_1f26df72 ON public.channels_syncevent USING btree (created_by_id);


--
-- Name: channels_syncevent_modified_by_id_3d34e239; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX channels_syncevent_modified_by_id_3d34e239 ON public.channels_syncevent USING btree (modified_by_id);


--
-- Name: classifiers_classifier_created_by_id_70c864b9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX classifiers_classifier_created_by_id_70c864b9 ON public.classifiers_classifier USING btree (created_by_id);


--
-- Name: classifiers_classifier_modified_by_id_8adf4397; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX classifiers_classifier_modified_by_id_8adf4397 ON public.classifiers_classifier USING btree (modified_by_id);


--
-- Name: classifiers_classifier_org_id_0cffa81e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX classifiers_classifier_org_id_0cffa81e ON public.classifiers_classifier USING btree (org_id);


--
-- Name: classifiers_intent_classifier_id_4be65c6f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX classifiers_intent_classifier_id_4be65c6f ON public.classifiers_intent USING btree (classifier_id);


--
-- Name: contact_fields_keys_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contact_fields_keys_idx ON public.contacts_contact USING gin (public.extract_jsonb_keys(fields));


--
-- Name: contacts_contact_created_by_id_57537352; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_created_by_id_57537352 ON public.contacts_contact USING btree (created_by_id);


--
-- Name: contacts_contact_modified_by_id_db5cbe12; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_modified_by_id_db5cbe12 ON public.contacts_contact USING btree (modified_by_id);


--
-- Name: contacts_contact_modified_on; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_modified_on ON public.contacts_contact USING btree (modified_on);


--
-- Name: contacts_contact_org_id_01d86aa4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_org_id_01d86aa4 ON public.contacts_contact USING btree (org_id);


--
-- Name: contacts_contact_org_modified; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_org_modified ON public.contacts_contact USING btree (org_id, modified_on DESC);


--
-- Name: contacts_contact_org_modified_id_active; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_org_modified_id_active ON public.contacts_contact USING btree (org_id, modified_on DESC, id DESC) WHERE (is_active = true);


--
-- Name: contacts_contact_org_modified_id_inactive; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_org_modified_id_inactive ON public.contacts_contact USING btree (org_id, modified_on DESC, id DESC) WHERE (is_active = false);


--
-- Name: contacts_contact_uuid_66fe2f01_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contact_uuid_66fe2f01_like ON public.contacts_contact USING btree (uuid varchar_pattern_ops);


--
-- Name: contacts_contactfield_created_by_id_7bce7fd0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactfield_created_by_id_7bce7fd0 ON public.contacts_contactfield USING btree (created_by_id);


--
-- Name: contacts_contactfield_modified_by_id_99cfac9b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactfield_modified_by_id_99cfac9b ON public.contacts_contactfield USING btree (modified_by_id);


--
-- Name: contacts_contactfield_org_id_d83cc86a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactfield_org_id_d83cc86a ON public.contacts_contactfield USING btree (org_id);


--
-- Name: contacts_contactgroup_contacts_contact_id_572f6e61; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_contacts_contact_id_572f6e61 ON public.contacts_contactgroup_contacts USING btree (contact_id);


--
-- Name: contacts_contactgroup_contacts_contactgroup_id_4366e864; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_contacts_contactgroup_id_4366e864 ON public.contacts_contactgroup_contacts USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_created_by_id_6bbeef89; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_created_by_id_6bbeef89 ON public.contacts_contactgroup USING btree (created_by_id);


--
-- Name: contacts_contactgroup_modified_by_id_a765a76e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_modified_by_id_a765a76e ON public.contacts_contactgroup USING btree (modified_by_id);


--
-- Name: contacts_contactgroup_org_id_be850815; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_org_id_be850815 ON public.contacts_contactgroup USING btree (org_id);


--
-- Name: contacts_contactgroup_query_fields_contactfield_id_4e8430b1; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_query_fields_contactfield_id_4e8430b1 ON public.contacts_contactgroup_query_fields USING btree (contactfield_id);


--
-- Name: contacts_contactgroup_query_fields_contactgroup_id_94f3146d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_query_fields_contactgroup_id_94f3146d ON public.contacts_contactgroup_query_fields USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_uuid_377d4c62_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroup_uuid_377d4c62_like ON public.contacts_contactgroup USING btree (uuid varchar_pattern_ops);


--
-- Name: contacts_contactgroupcount_group_id_efcdb311; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroupcount_group_id_efcdb311 ON public.contacts_contactgroupcount USING btree (group_id);


--
-- Name: contacts_contactgroupcount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactgroupcount_unsquashed ON public.contacts_contactgroupcount USING btree (group_id) WHERE (NOT is_squashed);


--
-- Name: contacts_contactimport_created_by_id_a34024c3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactimport_created_by_id_a34024c3 ON public.contacts_contactimport USING btree (created_by_id);


--
-- Name: contacts_contactimport_group_id_4e75f45f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactimport_group_id_4e75f45f ON public.contacts_contactimport USING btree (group_id);


--
-- Name: contacts_contactimport_modified_by_id_6cf6a8d5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactimport_modified_by_id_6cf6a8d5 ON public.contacts_contactimport USING btree (modified_by_id);


--
-- Name: contacts_contactimport_org_id_b7820a48; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactimport_org_id_b7820a48 ON public.contacts_contactimport USING btree (org_id);


--
-- Name: contacts_contactimportbatch_contact_import_id_f863caf7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contactimportbatch_contact_import_id_f863caf7 ON public.contacts_contactimportbatch USING btree (contact_import_id);


--
-- Name: contacts_contacturn_channel_id_c3a417df; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contacturn_channel_id_c3a417df ON public.contacts_contacturn USING btree (channel_id);


--
-- Name: contacts_contacturn_contact_id_ae38055c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contacturn_contact_id_ae38055c ON public.contacts_contacturn USING btree (contact_id);


--
-- Name: contacts_contacturn_org_id_3cc60a3a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contacturn_org_id_3cc60a3a ON public.contacts_contacturn USING btree (org_id);


--
-- Name: contacts_contacturn_org_scheme_display; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contacturn_org_scheme_display ON public.contacts_contacturn USING btree (org_id, scheme, display) WHERE (display IS NOT NULL);


--
-- Name: contacts_contacturn_path; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_contacturn_path ON public.contacts_contacturn USING btree (org_id, upper((path)::text), contact_id);


--
-- Name: contacts_exportcontactstas_contactgroup_id_ce69ae43; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstas_contactgroup_id_ce69ae43 ON public.contacts_exportcontactstask_group_memberships USING btree (contactgroup_id);


--
-- Name: contacts_exportcontactstas_exportcontactstask_id_130a97d6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstas_exportcontactstask_id_130a97d6 ON public.contacts_exportcontactstask_group_memberships USING btree (exportcontactstask_id);


--
-- Name: contacts_exportcontactstask_created_by_id_c2721c08; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstask_created_by_id_c2721c08 ON public.contacts_exportcontactstask USING btree (created_by_id);


--
-- Name: contacts_exportcontactstask_group_id_f623b2c1; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstask_group_id_f623b2c1 ON public.contacts_exportcontactstask USING btree (group_id);


--
-- Name: contacts_exportcontactstask_modified_by_id_212a480d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstask_modified_by_id_212a480d ON public.contacts_exportcontactstask USING btree (modified_by_id);


--
-- Name: contacts_exportcontactstask_org_id_07dc65f7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstask_org_id_07dc65f7 ON public.contacts_exportcontactstask USING btree (org_id);


--
-- Name: contacts_exportcontactstask_uuid_aad904fe_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX contacts_exportcontactstask_uuid_aad904fe_like ON public.contacts_exportcontactstask USING btree (uuid varchar_pattern_ops);


--
-- Name: csv_imports_importtask_created_by_id_9657a45f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX csv_imports_importtask_created_by_id_9657a45f ON public.csv_imports_importtask USING btree (created_by_id);


--
-- Name: csv_imports_importtask_modified_by_id_282ce6c3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX csv_imports_importtask_modified_by_id_282ce6c3 ON public.csv_imports_importtask USING btree (modified_by_id);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: django_site_domain_a2e37b91_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX django_site_domain_a2e37b91_like ON public.django_site USING btree (domain varchar_pattern_ops);


--
-- Name: flows_exportflowresultstas_exportflowresultstask_id_8d280d67; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstas_exportflowresultstask_id_8d280d67 ON public.flows_exportflowresultstask_flows USING btree (exportflowresultstask_id);


--
-- Name: flows_exportflowresultstask_created_by_id_43d8e1bd; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstask_created_by_id_43d8e1bd ON public.flows_exportflowresultstask USING btree (created_by_id);


--
-- Name: flows_exportflowresultstask_flows_flow_id_b4c9e790; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstask_flows_flow_id_b4c9e790 ON public.flows_exportflowresultstask_flows USING btree (flow_id);


--
-- Name: flows_exportflowresultstask_modified_by_id_f4871075; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstask_modified_by_id_f4871075 ON public.flows_exportflowresultstask USING btree (modified_by_id);


--
-- Name: flows_exportflowresultstask_org_id_3a816787; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstask_org_id_3a816787 ON public.flows_exportflowresultstask USING btree (org_id);


--
-- Name: flows_exportflowresultstask_uuid_ed7e2021_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_exportflowresultstask_uuid_ed7e2021_like ON public.flows_exportflowresultstask USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flow_channel_dependencies_channel_id_14006e38; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_channel_dependencies_channel_id_14006e38 ON public.flows_flow_channel_dependencies USING btree (channel_id);


--
-- Name: flows_flow_channel_dependencies_flow_id_764a1db2; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_channel_dependencies_flow_id_764a1db2 ON public.flows_flow_channel_dependencies USING btree (flow_id);


--
-- Name: flows_flow_classifier_dependencies_classifier_id_ff112811; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_classifier_dependencies_classifier_id_ff112811 ON public.flows_flow_classifier_dependencies USING btree (classifier_id);


--
-- Name: flows_flow_classifier_dependencies_flow_id_dfb6765f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_classifier_dependencies_flow_id_dfb6765f ON public.flows_flow_classifier_dependencies USING btree (flow_id);


--
-- Name: flows_flow_created_by_id_2e1adcb6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_created_by_id_2e1adcb6 ON public.flows_flow USING btree (created_by_id);


--
-- Name: flows_flow_field_dependencies_contactfield_id_c8b161eb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_field_dependencies_contactfield_id_c8b161eb ON public.flows_flow_field_dependencies USING btree (contactfield_id);


--
-- Name: flows_flow_field_dependencies_flow_id_ee6ccf51; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_field_dependencies_flow_id_ee6ccf51 ON public.flows_flow_field_dependencies USING btree (flow_id);


--
-- Name: flows_flow_flow_dependencies_from_flow_id_bee265be; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_flow_dependencies_from_flow_id_bee265be ON public.flows_flow_flow_dependencies USING btree (from_flow_id);


--
-- Name: flows_flow_flow_dependencies_to_flow_id_015ac795; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_flow_dependencies_to_flow_id_015ac795 ON public.flows_flow_flow_dependencies USING btree (to_flow_id);


--
-- Name: flows_flow_global_dependencies_flow_id_e4988650; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_global_dependencies_flow_id_e4988650 ON public.flows_flow_global_dependencies USING btree (flow_id);


--
-- Name: flows_flow_global_dependencies_global_id_7b0fb9cf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_global_dependencies_global_id_7b0fb9cf ON public.flows_flow_global_dependencies USING btree (global_id);


--
-- Name: flows_flow_group_dependencies_contactgroup_id_f00562b0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_group_dependencies_contactgroup_id_f00562b0 ON public.flows_flow_group_dependencies USING btree (contactgroup_id);


--
-- Name: flows_flow_group_dependencies_flow_id_de38b8ae; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_group_dependencies_flow_id_de38b8ae ON public.flows_flow_group_dependencies USING btree (flow_id);


--
-- Name: flows_flow_label_dependencies_flow_id_7e6aa4fb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_label_dependencies_flow_id_7e6aa4fb ON public.flows_flow_label_dependencies USING btree (flow_id);


--
-- Name: flows_flow_label_dependencies_label_id_6828c670; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_label_dependencies_label_id_6828c670 ON public.flows_flow_label_dependencies USING btree (label_id);


--
-- Name: flows_flow_labels_flow_id_b5b2fc3c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_labels_flow_id_b5b2fc3c ON public.flows_flow_labels USING btree (flow_id);


--
-- Name: flows_flow_labels_flowlabel_id_ce11c90a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_labels_flowlabel_id_ce11c90a ON public.flows_flow_labels USING btree (flowlabel_id);


--
-- Name: flows_flow_modified_by_id_493fb4b1; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_modified_by_id_493fb4b1 ON public.flows_flow USING btree (modified_by_id);


--
-- Name: flows_flow_org_id_51b9c589; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_org_id_51b9c589 ON public.flows_flow USING btree (org_id);


--
-- Name: flows_flow_saved_by_id_edb563b6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_saved_by_id_edb563b6 ON public.flows_flow USING btree (saved_by_id);


--
-- Name: flows_flow_template_dependencies_flow_id_57119aea; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_template_dependencies_flow_id_57119aea ON public.flows_flow_template_dependencies USING btree (flow_id);


--
-- Name: flows_flow_template_dependencies_template_id_0bc5b230; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_template_dependencies_template_id_0bc5b230 ON public.flows_flow_template_dependencies USING btree (template_id);


--
-- Name: flows_flow_ticketer_dependencies_flow_id_2da8a431; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_ticketer_dependencies_flow_id_2da8a431 ON public.flows_flow_ticketer_dependencies USING btree (flow_id);


--
-- Name: flows_flow_ticketer_dependencies_ticketer_id_359d030e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_ticketer_dependencies_ticketer_id_359d030e ON public.flows_flow_ticketer_dependencies USING btree (ticketer_id);


--
-- Name: flows_flow_topic_dependencies_flow_id_016caef9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_topic_dependencies_flow_id_016caef9 ON public.flows_flow_topic_dependencies USING btree (flow_id);


--
-- Name: flows_flow_topic_dependencies_topic_id_51eebe46; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_topic_dependencies_topic_id_51eebe46 ON public.flows_flow_topic_dependencies USING btree (topic_id);


--
-- Name: flows_flow_user_dependencies_flow_id_0e0ee262; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_user_dependencies_flow_id_0e0ee262 ON public.flows_flow_user_dependencies USING btree (flow_id);


--
-- Name: flows_flow_user_dependencies_user_id_9201056c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_user_dependencies_user_id_9201056c ON public.flows_flow_user_dependencies USING btree (user_id);


--
-- Name: flows_flow_uuid_a2114745_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flow_uuid_a2114745_like ON public.flows_flow USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flowcategorycount_flow_id_ae033ba6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowcategorycount_flow_id_ae033ba6 ON public.flows_flowcategorycount USING btree (flow_id);


--
-- Name: flows_flowcategorycount_node_uuid_85f59dfb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowcategorycount_node_uuid_85f59dfb ON public.flows_flowcategorycount USING btree (node_uuid);


--
-- Name: flows_flowcategorycount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowcategorycount_unsquashed ON public.flows_flowcategorycount USING btree (flow_id, node_uuid, result_key, result_name, category_name) WHERE (NOT is_squashed);


--
-- Name: flows_flowlabel_created_by_id_9a7b3325; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowlabel_created_by_id_9a7b3325 ON public.flows_flowlabel USING btree (created_by_id);


--
-- Name: flows_flowlabel_modified_by_id_84e574e7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowlabel_modified_by_id_84e574e7 ON public.flows_flowlabel USING btree (modified_by_id);


--
-- Name: flows_flowlabel_org_id_4ed2f553; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowlabel_org_id_4ed2f553 ON public.flows_flowlabel USING btree (org_id);


--
-- Name: flows_flowlabel_parent_id_73c0a2dd; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowlabel_parent_id_73c0a2dd ON public.flows_flowlabel USING btree (parent_id);


--
-- Name: flows_flowlabel_uuid_133646e5_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowlabel_uuid_133646e5_like ON public.flows_flowlabel USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flownodecount_flow_id_ba7a0620; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flownodecount_flow_id_ba7a0620 ON public.flows_flownodecount USING btree (flow_id);


--
-- Name: flows_flownodecount_node_uuid_7cfb23f7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flownodecount_node_uuid_7cfb23f7 ON public.flows_flownodecount USING btree (node_uuid);


--
-- Name: flows_flownodecount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flownodecount_unsquashed ON public.flows_flownodecount USING btree (flow_id, node_uuid) WHERE (NOT is_squashed);


--
-- Name: flows_flowpathcount_flow_id_09a7db20; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowpathcount_flow_id_09a7db20 ON public.flows_flowpathcount USING btree (flow_id);


--
-- Name: flows_flowpathcount_flow_id_from_uuid_to_uui_c2f02792_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowpathcount_flow_id_from_uuid_to_uui_c2f02792_idx ON public.flows_flowpathcount USING btree (flow_id, from_uuid, to_uuid, period);


--
-- Name: flows_flowpathcount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowpathcount_unsquashed ON public.flows_flowpathcount USING btree (flow_id, from_uuid, to_uuid, period) WHERE (NOT is_squashed);


--
-- Name: flows_flowrevision_created_by_id_fb31d40f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrevision_created_by_id_fb31d40f ON public.flows_flowrevision USING btree (created_by_id);


--
-- Name: flows_flowrevision_flow_id_4ae332c8; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrevision_flow_id_4ae332c8 ON public.flows_flowrevision USING btree (flow_id);


--
-- Name: flows_flowrevision_modified_by_id_b5464873; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrevision_modified_by_id_b5464873 ON public.flows_flowrevision USING btree (modified_by_id);


--
-- Name: flows_flowrun_contact_inc_flow; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_contact_inc_flow ON public.flows_flowrun USING btree (contact_id) INCLUDE (flow_id);


--
-- Name: flows_flowrun_contacts_at_node; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_contacts_at_node ON public.flows_flowrun USING btree (org_id, current_node_uuid) INCLUDE (contact_id) WHERE ((status)::text = ANY ((ARRAY['A'::character varying, 'W'::character varying])::text[]));


--
-- Name: flows_flowrun_flow_id_9cbb3a32; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_flow_id_9cbb3a32 ON public.flows_flowrun USING btree (flow_id);


--
-- Name: flows_flowrun_flow_modified_id; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_flow_modified_id ON public.flows_flowrun USING btree (flow_id, modified_on DESC, id DESC);


--
-- Name: flows_flowrun_flow_modified_id_where_responded; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_flow_modified_id_where_responded ON public.flows_flowrun USING btree (flow_id, modified_on DESC, id DESC) WHERE (responded = true);


--
-- Name: flows_flowrun_org_modified_id; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_org_modified_id ON public.flows_flowrun USING btree (org_id, modified_on DESC, id DESC);


--
-- Name: flows_flowrun_org_modified_id_where_responded; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_org_modified_id_where_responded ON public.flows_flowrun USING btree (org_id, modified_on DESC, id DESC) WHERE (responded = true);


--
-- Name: flows_flowrun_session_id_ef240528; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_session_id_ef240528 ON public.flows_flowrun USING btree (session_id);


--
-- Name: flows_flowrun_start_id_6f5f00b9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowrun_start_id_6f5f00b9 ON public.flows_flowrun USING btree (start_id);


--
-- Name: flows_flowruncount_flow_id_6a87383f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowruncount_flow_id_6a87383f ON public.flows_flowruncount USING btree (flow_id);


--
-- Name: flows_flowruncount_flow_id_exit_type_eef1051f_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowruncount_flow_id_exit_type_eef1051f_idx ON public.flows_flowruncount USING btree (flow_id, exit_type);


--
-- Name: flows_flowruncount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowruncount_unsquashed ON public.flows_flowruncount USING btree (flow_id, exit_type) WHERE (NOT is_squashed);


--
-- Name: flows_flowsession_contact_id_290da86f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_contact_id_290da86f ON public.flows_flowsession USING btree (contact_id);


--
-- Name: flows_flowsession_current_flow_id_4e32c60b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_current_flow_id_4e32c60b ON public.flows_flowsession USING btree (current_flow_id);


--
-- Name: flows_flowsession_ended_on_not_null; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_ended_on_not_null ON public.flows_flowsession USING btree (ended_on) WHERE (ended_on IS NOT NULL);


--
-- Name: flows_flowsession_org_id_9785ea64; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_org_id_9785ea64 ON public.flows_flowsession USING btree (org_id);


--
-- Name: flows_flowsession_timeout; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_timeout ON public.flows_flowsession USING btree (timeout_on) WHERE ((timeout_on IS NOT NULL) AND ((status)::text = 'W'::text));


--
-- Name: flows_flowsession_waiting; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowsession_waiting ON public.flows_flowsession USING btree (contact_id) WHERE ((status)::text = 'W'::text);


--
-- Name: flows_flowstart_campaign_event_id_70ae0d00; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_campaign_event_id_70ae0d00 ON public.flows_flowstart USING btree (campaign_event_id);


--
-- Name: flows_flowstart_connections_channelconnection_id_f97be856; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_connections_channelconnection_id_f97be856 ON public.flows_flowstart_connections USING btree (channelconnection_id);


--
-- Name: flows_flowstart_connections_flowstart_id_f8ef00d6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_connections_flowstart_id_f8ef00d6 ON public.flows_flowstart_connections USING btree (flowstart_id);


--
-- Name: flows_flowstart_contacts_contact_id_82879510; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_contacts_contact_id_82879510 ON public.flows_flowstart_contacts USING btree (contact_id);


--
-- Name: flows_flowstart_contacts_flowstart_id_d8b4cf8f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_contacts_flowstart_id_d8b4cf8f ON public.flows_flowstart_contacts USING btree (flowstart_id);


--
-- Name: flows_flowstart_created_by_id_4eb88868; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_created_by_id_4eb88868 ON public.flows_flowstart USING btree (created_by_id);


--
-- Name: flows_flowstart_flow_id_c74e7d30; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_flow_id_c74e7d30 ON public.flows_flowstart USING btree (flow_id);


--
-- Name: flows_flowstart_groups_contactgroup_id_e2252838; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_groups_contactgroup_id_e2252838 ON public.flows_flowstart_groups USING btree (contactgroup_id);


--
-- Name: flows_flowstart_groups_flowstart_id_b44aad1f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_groups_flowstart_id_b44aad1f ON public.flows_flowstart_groups USING btree (flowstart_id);


--
-- Name: flows_flowstart_org_id_d5383c58; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_org_id_d5383c58 ON public.flows_flowstart USING btree (org_id);


--
-- Name: flows_flowstart_org_start_type; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstart_org_start_type ON public.flows_flowstart USING btree (org_id, start_type, created_on DESC);


--
-- Name: flows_flowstartcount_start_id_a149293f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstartcount_start_id_a149293f ON public.flows_flowstartcount USING btree (start_id);


--
-- Name: flows_flowstartcount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstartcount_unsquashed ON public.flows_flowstartcount USING btree (start_id) WHERE (NOT is_squashed);


--
-- Name: flows_flowstarts_org_created; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstarts_org_created ON public.flows_flowstart USING btree (org_id, created_on DESC) WHERE (created_by_id IS NOT NULL);


--
-- Name: flows_flowstarts_org_modified; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_flowstarts_org_modified ON public.flows_flowstart USING btree (org_id, modified_on DESC) WHERE (created_by_id IS NOT NULL);


--
-- Name: flows_session_message_expires; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_session_message_expires ON public.flows_flowsession USING btree (wait_expires_on) WHERE (((session_type)::text = 'M'::text) AND ((status)::text = 'W'::text) AND (wait_expires_on IS NOT NULL));


--
-- Name: flows_session_voice_expires; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX flows_session_voice_expires ON public.flows_flowsession USING btree (wait_expires_on) WHERE (((session_type)::text = 'V'::text) AND ((status)::text = 'W'::text) AND (wait_expires_on IS NOT NULL));


--
-- Name: globals_global_created_by_id_e948d660; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX globals_global_created_by_id_e948d660 ON public.globals_global USING btree (created_by_id);


--
-- Name: globals_global_modified_by_id_dca008ea; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX globals_global_modified_by_id_dca008ea ON public.globals_global USING btree (modified_by_id);


--
-- Name: globals_global_org_id_aa26748d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX globals_global_org_id_aa26748d ON public.globals_global USING btree (org_id);


--
-- Name: httplog_org_flows_only; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX httplog_org_flows_only ON public.request_logs_httplog USING btree (org_id, created_on DESC) WHERE (flow_id IS NOT NULL);


--
-- Name: incidents_ongoing; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX incidents_ongoing ON public.notifications_incident USING btree (incident_type) WHERE (ended_on IS NULL);


--
-- Name: incidents_ongoing_scoped; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX incidents_ongoing_scoped ON public.notifications_incident USING btree (org_id, incident_type, scope) WHERE (ended_on IS NULL);


--
-- Name: incidents_org_ended; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX incidents_org_ended ON public.notifications_incident USING btree (org_id, started_on DESC) WHERE (ended_on IS NOT NULL);


--
-- Name: incidents_org_ongoing; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX incidents_org_ongoing ON public.notifications_incident USING btree (org_id, started_on DESC) WHERE (ended_on IS NULL);


--
-- Name: locations_adminboundary_name; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_adminboundary_name ON public.locations_adminboundary USING btree (upper((name)::text));


--
-- Name: locations_adminboundary_osm_id_ada345c4_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_adminboundary_osm_id_ada345c4_like ON public.locations_adminboundary USING btree (osm_id varchar_pattern_ops);


--
-- Name: locations_adminboundary_parent_id_03a6640e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_adminboundary_parent_id_03a6640e ON public.locations_adminboundary USING btree (parent_id);


--
-- Name: locations_adminboundary_simplified_geometry_b093560d_id; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_adminboundary_simplified_geometry_b093560d_id ON public.locations_adminboundary USING gist (simplified_geometry);


--
-- Name: locations_adminboundary_tree_id_46103e14; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_adminboundary_tree_id_46103e14 ON public.locations_adminboundary USING btree (tree_id);


--
-- Name: locations_boundaryalias_boundary_id_7ba2d352; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_boundaryalias_boundary_id_7ba2d352 ON public.locations_boundaryalias USING btree (boundary_id);


--
-- Name: locations_boundaryalias_created_by_id_46911c69; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_boundaryalias_created_by_id_46911c69 ON public.locations_boundaryalias USING btree (created_by_id);


--
-- Name: locations_boundaryalias_modified_by_id_fabf1a13; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_boundaryalias_modified_by_id_fabf1a13 ON public.locations_boundaryalias USING btree (modified_by_id);


--
-- Name: locations_boundaryalias_name; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_boundaryalias_name ON public.locations_boundaryalias USING btree (upper((name)::text));


--
-- Name: locations_boundaryalias_org_id_930a8491; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX locations_boundaryalias_org_id_930a8491 ON public.locations_boundaryalias USING btree (org_id);


--
-- Name: msgs_broadcast_channel_id_896f7d11; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_channel_id_896f7d11 ON public.msgs_broadcast USING btree (channel_id);


--
-- Name: msgs_broadcast_contacts_broadcast_id_c5dc5132; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_contacts_broadcast_id_c5dc5132 ON public.msgs_broadcast_contacts USING btree (broadcast_id);


--
-- Name: msgs_broadcast_contacts_contact_id_9ffd3873; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_contacts_contact_id_9ffd3873 ON public.msgs_broadcast_contacts USING btree (contact_id);


--
-- Name: msgs_broadcast_created_by_id_bc4d5bb1; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_created_by_id_bc4d5bb1 ON public.msgs_broadcast USING btree (created_by_id);


--
-- Name: msgs_broadcast_created_on_e75b72a9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_created_on_e75b72a9 ON public.msgs_broadcast USING btree (created_on);


--
-- Name: msgs_broadcast_groups_broadcast_id_1b1d150a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_groups_broadcast_id_1b1d150a ON public.msgs_broadcast_groups USING btree (broadcast_id);


--
-- Name: msgs_broadcast_groups_contactgroup_id_c8187bee; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_groups_contactgroup_id_c8187bee ON public.msgs_broadcast_groups USING btree (contactgroup_id);


--
-- Name: msgs_broadcast_modified_by_id_b51c67df; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_modified_by_id_b51c67df ON public.msgs_broadcast USING btree (modified_by_id);


--
-- Name: msgs_broadcast_org_id_78c94f15; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_org_id_78c94f15 ON public.msgs_broadcast USING btree (org_id);


--
-- Name: msgs_broadcast_parent_id_a2f08782; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_parent_id_a2f08782 ON public.msgs_broadcast USING btree (parent_id);


--
-- Name: msgs_broadcast_sending_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_sending_idx ON public.msgs_broadcast USING btree (org_id, created_on) WHERE ((status)::text = 'Q'::text);


--
-- Name: msgs_broadcast_ticket_id_85a185ac; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_ticket_id_85a185ac ON public.msgs_broadcast USING btree (ticket_id);


--
-- Name: msgs_broadcast_urns_broadcast_id_aaf9d7b9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_urns_broadcast_id_aaf9d7b9 ON public.msgs_broadcast_urns USING btree (broadcast_id);


--
-- Name: msgs_broadcast_urns_contacturn_id_9fe60d63; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcast_urns_contacturn_id_9fe60d63 ON public.msgs_broadcast_urns USING btree (contacturn_id);


--
-- Name: msgs_broadcastmsgcount_broadcast_id_893c7af4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcastmsgcount_broadcast_id_893c7af4 ON public.msgs_broadcastmsgcount USING btree (broadcast_id);


--
-- Name: msgs_broadcasts_org_created_id; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_broadcasts_org_created_id ON public.msgs_broadcast USING btree (org_id, created_on DESC, id DESC);


--
-- Name: msgs_exportmessagestask_created_by_id_f3b48148; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_created_by_id_f3b48148 ON public.msgs_exportmessagestask USING btree (created_by_id);


--
-- Name: msgs_exportmessagestask_groups_contactgroup_id_3b816325; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_groups_contactgroup_id_3b816325 ON public.msgs_exportmessagestask_groups USING btree (contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups_exportmessagestask_id_3071019e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_groups_exportmessagestask_id_3071019e ON public.msgs_exportmessagestask_groups USING btree (exportmessagestask_id);


--
-- Name: msgs_exportmessagestask_label_id_80585f7d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_label_id_80585f7d ON public.msgs_exportmessagestask USING btree (label_id);


--
-- Name: msgs_exportmessagestask_modified_by_id_d76b3bdf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_modified_by_id_d76b3bdf ON public.msgs_exportmessagestask USING btree (modified_by_id);


--
-- Name: msgs_exportmessagestask_org_id_8b5afdca; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_org_id_8b5afdca ON public.msgs_exportmessagestask USING btree (org_id);


--
-- Name: msgs_exportmessagestask_uuid_a9d02f48_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_exportmessagestask_uuid_a9d02f48_like ON public.msgs_exportmessagestask USING btree (uuid varchar_pattern_ops);


--
-- Name: msgs_label_created_by_id_59cd46ee; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_label_created_by_id_59cd46ee ON public.msgs_label USING btree (created_by_id);


--
-- Name: msgs_label_folder_id_fef43746; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_label_folder_id_fef43746 ON public.msgs_label USING btree (folder_id);


--
-- Name: msgs_label_modified_by_id_8a4d5291; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_label_modified_by_id_8a4d5291 ON public.msgs_label USING btree (modified_by_id);


--
-- Name: msgs_label_org_id_a63db233; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_label_org_id_a63db233 ON public.msgs_label USING btree (org_id);


--
-- Name: msgs_label_uuid_d9a956c8_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_label_uuid_d9a956c8_like ON public.msgs_label USING btree (uuid varchar_pattern_ops);


--
-- Name: msgs_labelcount_label_id_3d012b42; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_labelcount_label_id_3d012b42 ON public.msgs_labelcount USING btree (label_id);


--
-- Name: msgs_msg_broadcast_id_7514e534; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_broadcast_id_7514e534 ON public.msgs_msg USING btree (broadcast_id);


--
-- Name: msgs_msg_channel_external_id_not_null; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_channel_external_id_not_null ON public.msgs_msg USING btree (channel_id, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: msgs_msg_channel_id_0592b6b0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_channel_id_0592b6b0 ON public.msgs_msg USING btree (channel_id);


--
-- Name: msgs_msg_contact_id_created_on; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_contact_id_created_on ON public.msgs_msg USING btree (contact_id, created_on DESC);


--
-- Name: msgs_msg_contact_urn_id_fc1da718; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_contact_urn_id_fc1da718 ON public.msgs_msg USING btree (contact_urn_id);


--
-- Name: msgs_msg_created_on_177d120b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_created_on_177d120b ON public.msgs_msg USING btree (created_on);


--
-- Name: msgs_msg_labels_label_id_525dfbc1; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_labels_label_id_525dfbc1 ON public.msgs_msg_labels USING btree (label_id);


--
-- Name: msgs_msg_labels_msg_id_a1f8fefa; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_labels_msg_id_a1f8fefa ON public.msgs_msg_labels USING btree (msg_id);


--
-- Name: msgs_msg_org_created_id_where_outbound_visible_failed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_org_created_id_where_outbound_visible_failed ON public.msgs_msg USING btree (org_id, created_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((visibility)::text = 'V'::text) AND ((status)::text = 'F'::text));


--
-- Name: msgs_msg_org_created_id_where_outbound_visible_outbox; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_org_created_id_where_outbound_visible_outbox ON public.msgs_msg USING btree (org_id, created_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((visibility)::text = 'V'::text) AND ((status)::text = ANY ((ARRAY['P'::character varying, 'Q'::character varying])::text[])));


--
-- Name: msgs_msg_org_id_created_on_id_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_org_id_created_on_id_idx ON public.msgs_msg USING btree (org_id, created_on, id);


--
-- Name: msgs_msg_org_id_d3488a20; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_org_id_d3488a20 ON public.msgs_msg USING btree (org_id);


--
-- Name: msgs_msg_org_modified_id_where_inbound; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_org_modified_id_where_inbound ON public.msgs_msg USING btree (org_id, modified_on DESC, id DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_msg_status_869a44ea; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_status_869a44ea ON public.msgs_msg USING btree (status);


--
-- Name: msgs_msg_status_869a44ea_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_status_869a44ea_like ON public.msgs_msg USING btree (status varchar_pattern_ops);


--
-- Name: msgs_msg_topup_id_0d2ccb2d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_topup_id_0d2ccb2d ON public.msgs_msg USING btree (topup_id);


--
-- Name: msgs_msg_visibility_type_created_id_where_inbound; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_msg_visibility_type_created_id_where_inbound ON public.msgs_msg USING btree (org_id, visibility, msg_type, created_on DESC, id DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_next_attempt_out_errored; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_next_attempt_out_errored ON public.msgs_msg USING btree (next_attempt, created_on, id) WHERE (((direction)::text = 'O'::text) AND (next_attempt IS NOT NULL) AND ((status)::text = 'E'::text));


--
-- Name: msgs_outgoing_visible_sent; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_outgoing_visible_sent ON public.msgs_msg USING btree (org_id, sent_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((status)::text = ANY ((ARRAY['W'::character varying, 'S'::character varying, 'D'::character varying])::text[])) AND ((visibility)::text = 'V'::text));


--
-- Name: msgs_systemlabel_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_systemlabel_unsquashed ON public.msgs_systemlabelcount USING btree (org_id, label_type) WHERE (NOT is_squashed);


--
-- Name: msgs_systemlabelcount_org_id_fed550a8; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_systemlabelcount_org_id_fed550a8 ON public.msgs_systemlabelcount USING btree (org_id);


--
-- Name: msgs_systemlabelcount_org_id_label_type_23117fff_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX msgs_systemlabelcount_org_id_label_type_23117fff_idx ON public.msgs_systemlabelcount USING btree (org_id, label_type);


--
-- Name: notificatio_org_id_17c9ee_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notificatio_org_id_17c9ee_idx ON public.notifications_notification USING btree (org_id, user_id, created_on DESC);


--
-- Name: notifications_email_pending; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_email_pending ON public.notifications_notification USING btree (created_on) WHERE ((email_status)::text = 'P'::text);


--
-- Name: notifications_incident_channel_id_52f252c5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_incident_channel_id_52f252c5 ON public.notifications_incident USING btree (channel_id);


--
-- Name: notifications_incident_org_id_b5cb2702; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_incident_org_id_b5cb2702 ON public.notifications_incident USING btree (org_id);


--
-- Name: notifications_notification_contact_export_id_f8a32d90; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_contact_export_id_f8a32d90 ON public.notifications_notification USING btree (contact_export_id);


--
-- Name: notifications_notification_contact_import_id_93e583b6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_contact_import_id_93e583b6 ON public.notifications_notification USING btree (contact_import_id);


--
-- Name: notifications_notification_incident_id_f5d6cdb9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_incident_id_f5d6cdb9 ON public.notifications_notification USING btree (incident_id);


--
-- Name: notifications_notification_message_export_id_1fb6515c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_message_export_id_1fb6515c ON public.notifications_notification USING btree (message_export_id);


--
-- Name: notifications_notification_org_id_b4c202e9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_org_id_b4c202e9 ON public.notifications_notification USING btree (org_id);


--
-- Name: notifications_notification_results_export_id_30213b45; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_results_export_id_30213b45 ON public.notifications_notification USING btree (results_export_id);


--
-- Name: notifications_notification_user_id_b5e8c0ff; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notification_user_id_b5e8c0ff ON public.notifications_notification USING btree (user_id);


--
-- Name: notifications_notificationcount_org_id_50b11add; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notificationcount_org_id_50b11add ON public.notifications_notificationcount USING btree (org_id);


--
-- Name: notifications_notificationcount_user_id_4aca02ba; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_notificationcount_user_id_4aca02ba ON public.notifications_notificationcount USING btree (user_id);


--
-- Name: notifications_unseen_of_type; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX notifications_unseen_of_type ON public.notifications_notification USING btree (org_id, notification_type, user_id) WHERE (NOT is_seen);


--
-- Name: notifications_unseen_scoped; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX notifications_unseen_scoped ON public.notifications_notification USING btree (org_id, notification_type, scope, user_id) WHERE (NOT is_seen);


--
-- Name: orgs_backuptoken_token_fe684786_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_backuptoken_token_fe684786_like ON public.orgs_backuptoken USING btree (token varchar_pattern_ops);


--
-- Name: orgs_backuptoken_user_id_2e881bc5; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_backuptoken_user_id_2e881bc5 ON public.orgs_backuptoken USING btree (user_id);


--
-- Name: orgs_creditalert_created_by_id_902a99c9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_creditalert_created_by_id_902a99c9 ON public.orgs_creditalert USING btree (created_by_id);


--
-- Name: orgs_creditalert_modified_by_id_a7b1b154; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_creditalert_modified_by_id_a7b1b154 ON public.orgs_creditalert USING btree (modified_by_id);


--
-- Name: orgs_creditalert_org_id_f6caae69; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_creditalert_org_id_f6caae69 ON public.orgs_creditalert USING btree (org_id);


--
-- Name: orgs_debit_beneficiary_id_b95fb2b4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_debit_beneficiary_id_b95fb2b4 ON public.orgs_debit USING btree (beneficiary_id);


--
-- Name: orgs_debit_created_by_id_6e727579; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_debit_created_by_id_6e727579 ON public.orgs_debit USING btree (created_by_id);


--
-- Name: orgs_debit_topup_id_be941fdc; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_debit_topup_id_be941fdc ON public.orgs_debit USING btree (topup_id);


--
-- Name: orgs_invitation_created_by_id_147e359a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_invitation_created_by_id_147e359a ON public.orgs_invitation USING btree (created_by_id);


--
-- Name: orgs_invitation_modified_by_id_dd8cae65; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_invitation_modified_by_id_dd8cae65 ON public.orgs_invitation USING btree (modified_by_id);


--
-- Name: orgs_invitation_org_id_d9d2be95; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_invitation_org_id_d9d2be95 ON public.orgs_invitation USING btree (org_id);


--
-- Name: orgs_invitation_secret_fa4b1204_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_invitation_secret_fa4b1204_like ON public.orgs_invitation USING btree (secret varchar_pattern_ops);


--
-- Name: orgs_org_administrators_org_id_df1333f0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_administrators_org_id_df1333f0 ON public.orgs_org_administrators USING btree (org_id);


--
-- Name: orgs_org_administrators_user_id_74fbbbcb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_administrators_user_id_74fbbbcb ON public.orgs_org_administrators USING btree (user_id);


--
-- Name: orgs_org_agents_org_id_009f15fa; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_agents_org_id_009f15fa ON public.orgs_org_agents USING btree (org_id);


--
-- Name: orgs_org_agents_user_id_1626becb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_agents_user_id_1626becb ON public.orgs_org_agents USING btree (user_id);


--
-- Name: orgs_org_country_id_c6e479af; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_country_id_c6e479af ON public.orgs_org USING btree (country_id);


--
-- Name: orgs_org_created_by_id_f738c068; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_created_by_id_f738c068 ON public.orgs_org USING btree (created_by_id);


--
-- Name: orgs_org_editors_org_id_2ac53adb; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_editors_org_id_2ac53adb ON public.orgs_org_editors USING btree (org_id);


--
-- Name: orgs_org_editors_user_id_21fb7e08; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_editors_user_id_21fb7e08 ON public.orgs_org_editors USING btree (user_id);


--
-- Name: orgs_org_modified_by_id_61e424e7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_modified_by_id_61e424e7 ON public.orgs_org USING btree (modified_by_id);


--
-- Name: orgs_org_parent_id_79ba1bbf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_parent_id_79ba1bbf ON public.orgs_org USING btree (parent_id);


--
-- Name: orgs_org_slug_203caf0d_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_slug_203caf0d_like ON public.orgs_org USING btree (slug varchar_pattern_ops);


--
-- Name: orgs_org_surveyors_org_id_80c50287; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_surveyors_org_id_80c50287 ON public.orgs_org_surveyors USING btree (org_id);


--
-- Name: orgs_org_surveyors_user_id_78800efa; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_surveyors_user_id_78800efa ON public.orgs_org_surveyors USING btree (user_id);


--
-- Name: orgs_org_viewers_org_id_d7604492; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_viewers_org_id_d7604492 ON public.orgs_org_viewers USING btree (org_id);


--
-- Name: orgs_org_viewers_user_id_0650bd4d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_org_viewers_user_id_0650bd4d ON public.orgs_org_viewers USING btree (user_id);


--
-- Name: orgs_orgactivity_org_id_1596e05b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_orgactivity_org_id_1596e05b ON public.orgs_orgactivity USING btree (org_id);


--
-- Name: orgs_orgmembership_org_id_35cc8172; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_orgmembership_org_id_35cc8172 ON public.orgs_orgmembership USING btree (org_id);


--
-- Name: orgs_orgmembership_user_id_ebcaadcf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_orgmembership_user_id_ebcaadcf ON public.orgs_orgmembership USING btree (user_id);


--
-- Name: orgs_topup_created_by_id_026008e4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_topup_created_by_id_026008e4 ON public.orgs_topup USING btree (created_by_id);


--
-- Name: orgs_topup_modified_by_id_c6b91b30; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_topup_modified_by_id_c6b91b30 ON public.orgs_topup USING btree (modified_by_id);


--
-- Name: orgs_topup_org_id_cde450ed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_topup_org_id_cde450ed ON public.orgs_topup USING btree (org_id);


--
-- Name: orgs_topupcredits_topup_id_9b2e5f7d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_topupcredits_topup_id_9b2e5f7d ON public.orgs_topupcredits USING btree (topup_id);


--
-- Name: orgs_topupcredits_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_topupcredits_unsquashed ON public.orgs_topupcredits USING btree (topup_id) WHERE (NOT is_squashed);


--
-- Name: orgs_usersettings_team_id_cf1e2965; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_usersettings_team_id_cf1e2965 ON public.orgs_usersettings USING btree (team_id);


--
-- Name: orgs_usersettings_user_id_ef7b03af; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX orgs_usersettings_user_id_ef7b03af ON public.orgs_usersettings USING btree (user_id);


--
-- Name: policies_consent_policy_id_cf6ba8c2; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX policies_consent_policy_id_cf6ba8c2 ON public.policies_consent USING btree (policy_id);


--
-- Name: policies_consent_user_id_ae612331; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX policies_consent_user_id_ae612331 ON public.policies_consent USING btree (user_id);


--
-- Name: policies_policy_created_by_id_3e6781aa; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX policies_policy_created_by_id_3e6781aa ON public.policies_policy USING btree (created_by_id);


--
-- Name: policies_policy_modified_by_id_67fe46ae; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX policies_policy_modified_by_id_67fe46ae ON public.policies_policy USING btree (modified_by_id);


--
-- Name: public_lead_created_by_id_2da6cfc7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX public_lead_created_by_id_2da6cfc7 ON public.public_lead USING btree (created_by_id);


--
-- Name: public_lead_modified_by_id_934f2f0c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX public_lead_modified_by_id_934f2f0c ON public.public_lead USING btree (modified_by_id);


--
-- Name: public_video_created_by_id_11455096; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX public_video_created_by_id_11455096 ON public.public_video USING btree (created_by_id);


--
-- Name: public_video_modified_by_id_7009d0a7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX public_video_modified_by_id_7009d0a7 ON public.public_video USING btree (modified_by_id);


--
-- Name: request_log_classif_8a1320_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_log_classif_8a1320_idx ON public.request_logs_httplog USING btree (classifier_id, created_on DESC);


--
-- Name: request_log_tickete_abc69b_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_log_tickete_abc69b_idx ON public.request_logs_httplog USING btree (ticketer_id, created_on DESC);


--
-- Name: request_logs_httplog_airtime_transfer_id_4fc31c64; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_logs_httplog_airtime_transfer_id_4fc31c64 ON public.request_logs_httplog USING btree (airtime_transfer_id);


--
-- Name: request_logs_httplog_channel_id_551e481b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_logs_httplog_channel_id_551e481b ON public.request_logs_httplog USING btree (channel_id);


--
-- Name: request_logs_httplog_flow_id_0694ff8c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_logs_httplog_flow_id_0694ff8c ON public.request_logs_httplog USING btree (flow_id);


--
-- Name: request_logs_httplog_org_id_2ad1fbae; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX request_logs_httplog_org_id_2ad1fbae ON public.request_logs_httplog USING btree (org_id);


--
-- Name: schedules_next_fire_active; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX schedules_next_fire_active ON public.schedules_schedule USING btree (next_fire) WHERE (is_active AND (next_fire IS NOT NULL));


--
-- Name: schedules_schedule_created_by_id_7a808dd9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX schedules_schedule_created_by_id_7a808dd9 ON public.schedules_schedule USING btree (created_by_id);


--
-- Name: schedules_schedule_modified_by_id_75f3d89a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX schedules_schedule_modified_by_id_75f3d89a ON public.schedules_schedule USING btree (modified_by_id);


--
-- Name: schedules_schedule_org_id_bb6269db; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX schedules_schedule_org_id_bb6269db ON public.schedules_schedule USING btree (org_id);


--
-- Name: templates_template_org_id_01fb381e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX templates_template_org_id_01fb381e ON public.templates_template USING btree (org_id);


--
-- Name: templates_templatetranslation_channel_id_07917e3a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX templates_templatetranslation_channel_id_07917e3a ON public.templates_templatetranslation USING btree (channel_id);


--
-- Name: templates_templatetranslation_template_id_66a162f6; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX templates_templatetranslation_template_id_66a162f6 ON public.templates_templatetranslation USING btree (template_id);


--
-- Name: ticket_count_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX ticket_count_unsquashed ON public.tickets_ticketcount USING btree (org_id, assignee_id, status) WHERE (NOT is_squashed);


--
-- Name: ticketevents_contact_created; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX ticketevents_contact_created ON public.tickets_ticketevent USING btree (contact_id, created_on);


--
-- Name: tickets_contact_open; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_contact_open ON public.tickets_ticket USING btree (contact_id, opened_on DESC) WHERE ((status)::text = 'O'::text);


--
-- Name: tickets_dailycount_type_scope; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_dailycount_type_scope ON public.tickets_ticketdailycount USING btree (count_type, scope, day);


--
-- Name: tickets_dailycount_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_dailycount_unsquashed ON public.tickets_ticketdailycount USING btree (count_type, scope, day) WHERE (NOT is_squashed);


--
-- Name: tickets_dailytiming_type_scope; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_dailytiming_type_scope ON public.tickets_ticketdailytiming USING btree (count_type, scope, day);


--
-- Name: tickets_dailytiming_unsquashed; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_dailytiming_unsquashed ON public.tickets_ticketdailytiming USING btree (count_type, scope, day) WHERE (NOT is_squashed);


--
-- Name: tickets_org_assignee_status; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_org_assignee_status ON public.tickets_ticket USING btree (org_id, assignee_id, status, last_activity_on DESC, id DESC);


--
-- Name: tickets_org_status; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_org_status ON public.tickets_ticket USING btree (org_id, status, last_activity_on DESC, id DESC);


--
-- Name: tickets_team_created_by_id_6e92ba12; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_team_created_by_id_6e92ba12 ON public.tickets_team USING btree (created_by_id);


--
-- Name: tickets_team_modified_by_id_99a64cad; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_team_modified_by_id_99a64cad ON public.tickets_team USING btree (modified_by_id);


--
-- Name: tickets_team_org_id_2a011111; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_team_org_id_2a011111 ON public.tickets_team USING btree (org_id);


--
-- Name: tickets_team_topics_team_id_ea473ed0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_team_topics_team_id_ea473ed0 ON public.tickets_team_topics USING btree (team_id);


--
-- Name: tickets_team_topics_topic_id_7c317c54; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_team_topics_topic_id_7c317c54 ON public.tickets_team_topics USING btree (topic_id);


--
-- Name: tickets_tic_org_id_3bdc4d_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_tic_org_id_3bdc4d_idx ON public.tickets_ticketcount USING btree (org_id, status);


--
-- Name: tickets_tic_org_id_6e466a_idx; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_tic_org_id_6e466a_idx ON public.tickets_ticketcount USING btree (org_id, assignee_id, status);


--
-- Name: tickets_ticket_assignee_id_3a5aa407; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticket_assignee_id_3a5aa407 ON public.tickets_ticket USING btree (assignee_id);


--
-- Name: tickets_ticket_contact_id_a9a8a57d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticket_contact_id_a9a8a57d ON public.tickets_ticket USING btree (contact_id);


--
-- Name: tickets_ticket_org_id_56b25ecf; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticket_org_id_56b25ecf ON public.tickets_ticket USING btree (org_id);


--
-- Name: tickets_ticket_ticketer_id_0c8d390f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticket_ticketer_id_0c8d390f ON public.tickets_ticket USING btree (ticketer_id);


--
-- Name: tickets_ticket_topic_id_80564e0d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticket_topic_id_80564e0d ON public.tickets_ticket USING btree (topic_id);


--
-- Name: tickets_ticketcount_assignee_id_94b9a29c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketcount_assignee_id_94b9a29c ON public.tickets_ticketcount USING btree (assignee_id);


--
-- Name: tickets_ticketcount_org_id_45a131d2; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketcount_org_id_45a131d2 ON public.tickets_ticketcount USING btree (org_id);


--
-- Name: tickets_ticketer_created_by_id_65853966; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketer_created_by_id_65853966 ON public.tickets_ticketer USING btree (created_by_id);


--
-- Name: tickets_ticketer_external_id; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketer_external_id ON public.tickets_ticket USING btree (ticketer_id, external_id);


--
-- Name: tickets_ticketer_modified_by_id_41ab9a7e; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketer_modified_by_id_41ab9a7e ON public.tickets_ticketer USING btree (modified_by_id);


--
-- Name: tickets_ticketer_org_id_00771428; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketer_org_id_00771428 ON public.tickets_ticketer USING btree (org_id);


--
-- Name: tickets_ticketevent_assignee_id_5b6836f3; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_assignee_id_5b6836f3 ON public.tickets_ticketevent USING btree (assignee_id);


--
-- Name: tickets_ticketevent_contact_id_a5104bc7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_contact_id_a5104bc7 ON public.tickets_ticketevent USING btree (contact_id);


--
-- Name: tickets_ticketevent_created_by_id_1dd8436d; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_created_by_id_1dd8436d ON public.tickets_ticketevent USING btree (created_by_id);


--
-- Name: tickets_ticketevent_org_id_58f88b39; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_org_id_58f88b39 ON public.tickets_ticketevent USING btree (org_id);


--
-- Name: tickets_ticketevent_ticket_id_b572d14b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_ticket_id_b572d14b ON public.tickets_ticketevent USING btree (ticket_id);


--
-- Name: tickets_ticketevent_topic_id_ce719f3b; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_ticketevent_topic_id_ce719f3b ON public.tickets_ticketevent USING btree (topic_id);


--
-- Name: tickets_topic_created_by_id_a7daf971; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_topic_created_by_id_a7daf971 ON public.tickets_topic USING btree (created_by_id);


--
-- Name: tickets_topic_modified_by_id_409a6eb0; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_topic_modified_by_id_409a6eb0 ON public.tickets_topic USING btree (modified_by_id);


--
-- Name: tickets_topic_org_id_0b22bd8a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX tickets_topic_org_id_0b22bd8a ON public.tickets_topic USING btree (org_id);


--
-- Name: triggers_trigger_channel_id_1e8206f8; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_channel_id_1e8206f8 ON public.triggers_trigger USING btree (channel_id);


--
-- Name: triggers_trigger_contacts_contact_id_58bca9a4; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_contacts_contact_id_58bca9a4 ON public.triggers_trigger_contacts USING btree (contact_id);


--
-- Name: triggers_trigger_contacts_trigger_id_2d7952cd; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_contacts_trigger_id_2d7952cd ON public.triggers_trigger_contacts USING btree (trigger_id);


--
-- Name: triggers_trigger_created_by_id_265631d7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_created_by_id_265631d7 ON public.triggers_trigger USING btree (created_by_id);


--
-- Name: triggers_trigger_exclude_groups_contactgroup_id_b62cd1da; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_exclude_groups_contactgroup_id_b62cd1da ON public.triggers_trigger_exclude_groups USING btree (contactgroup_id);


--
-- Name: triggers_trigger_exclude_groups_trigger_id_753d099a; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_exclude_groups_trigger_id_753d099a ON public.triggers_trigger_exclude_groups USING btree (trigger_id);


--
-- Name: triggers_trigger_flow_id_89d39d82; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_flow_id_89d39d82 ON public.triggers_trigger USING btree (flow_id);


--
-- Name: triggers_trigger_groups_contactgroup_id_648b9858; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_groups_contactgroup_id_648b9858 ON public.triggers_trigger_groups USING btree (contactgroup_id);


--
-- Name: triggers_trigger_groups_trigger_id_e3f9e0a9; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_groups_trigger_id_e3f9e0a9 ON public.triggers_trigger_groups USING btree (trigger_id);


--
-- Name: triggers_trigger_modified_by_id_6a5f982f; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_modified_by_id_6a5f982f ON public.triggers_trigger USING btree (modified_by_id);


--
-- Name: triggers_trigger_org_id_4a23f4c2; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX triggers_trigger_org_id_4a23f4c2 ON public.triggers_trigger USING btree (org_id);


--
-- Name: unique_contact_group_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_contact_group_names ON public.contacts_contactgroup USING btree (org_id, lower((name)::text));


--
-- Name: unique_flow_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_flow_names ON public.flows_flow USING btree (org_id, lower((name)::text));


--
-- Name: unique_flowlabel_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_flowlabel_names ON public.flows_flowlabel USING btree (org_id, lower((name)::text));


--
-- Name: unique_label_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_label_names ON public.msgs_label USING btree (org_id, lower((name)::text));


--
-- Name: unique_team_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_team_names ON public.tickets_team USING btree (org_id, lower((name)::text));


--
-- Name: unique_topic_names; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE UNIQUE INDEX unique_topic_names ON public.tickets_topic USING btree (org_id, lower((name)::text));


--
-- Name: users_passwordhistory_user_id_1396dbb7; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX users_passwordhistory_user_id_1396dbb7 ON public.users_passwordhistory USING btree (user_id);


--
-- Name: users_recoverytoken_token_c8594dc8_like; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX users_recoverytoken_token_c8594dc8_like ON public.users_recoverytoken USING btree (token varchar_pattern_ops);


--
-- Name: users_recoverytoken_user_id_0d7bef8c; Type: INDEX; Schema: public; Owner: flowartisan
--

CREATE INDEX users_recoverytoken_user_id_0d7bef8c ON public.users_recoverytoken USING btree (user_id);


--
-- Name: msgs_broadcast temba_broadcast_on_change_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_broadcast_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON public.msgs_broadcast FOR EACH ROW EXECUTE FUNCTION public.temba_broadcast_on_change();


--
-- Name: channels_channelevent temba_channelevent_on_change_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_channelevent_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON public.channels_channelevent FOR EACH ROW EXECUTE FUNCTION public.temba_channelevent_on_change();


--
-- Name: channels_channellog temba_channellog_update_channelcount; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_channellog_update_channelcount AFTER INSERT OR DELETE OR UPDATE OF is_error, channel_id ON public.channels_channellog FOR EACH ROW EXECUTE FUNCTION public.temba_update_channellog_count();


--
-- Name: flows_flowrun temba_flowrun_delete; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_flowrun_delete AFTER DELETE ON public.flows_flowrun FOR EACH ROW EXECUTE FUNCTION public.temba_flowrun_delete();


--
-- Name: flows_flowrun temba_flowrun_insert; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_flowrun_insert AFTER INSERT ON public.flows_flowrun FOR EACH ROW EXECUTE FUNCTION public.temba_flowrun_insert();


--
-- Name: flows_flowrun temba_flowrun_path_change; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_flowrun_path_change AFTER UPDATE OF path, status ON public.flows_flowrun FOR EACH ROW EXECUTE FUNCTION public.temba_flowrun_path_change();


--
-- Name: flows_flowrun temba_flowrun_status_change; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_flowrun_status_change AFTER UPDATE OF status ON public.flows_flowrun FOR EACH ROW EXECUTE FUNCTION public.temba_flowrun_status_change();


--
-- Name: flows_flowrun temba_flowrun_update_flowcategorycount; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_flowrun_update_flowcategorycount AFTER INSERT OR UPDATE OF results ON public.flows_flowrun FOR EACH ROW EXECUTE FUNCTION public.temba_update_flowcategorycount();


--
-- Name: msgs_msg_labels temba_msg_labels_on_change_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_msg_labels_on_change_trg AFTER INSERT OR DELETE ON public.msgs_msg_labels FOR EACH ROW EXECUTE FUNCTION public.temba_msg_labels_on_change();


--
-- Name: msgs_msg temba_msg_on_change_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_msg_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON public.msgs_msg FOR EACH ROW EXECUTE FUNCTION public.temba_msg_on_change();


--
-- Name: msgs_msg temba_msg_update_channelcount; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_msg_update_channelcount AFTER INSERT OR DELETE OR UPDATE OF direction, msg_type, created_on ON public.msgs_msg FOR EACH ROW EXECUTE FUNCTION public.temba_update_channelcount();


--
-- Name: notifications_notification temba_notifications_update_notificationcount; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_notifications_update_notificationcount AFTER INSERT OR DELETE OR UPDATE OF is_seen ON public.notifications_notification FOR EACH ROW EXECUTE FUNCTION public.temba_notification_on_change();


--
-- Name: tickets_ticket temba_ticket_on_change_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_ticket_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON public.tickets_ticket FOR EACH ROW EXECUTE FUNCTION public.temba_ticket_on_change();


--
-- Name: orgs_debit temba_when_debit_update_then_update_topupcredits_for_debit; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_when_debit_update_then_update_topupcredits_for_debit AFTER INSERT OR DELETE OR UPDATE OF topup_id ON public.orgs_debit FOR EACH ROW EXECUTE FUNCTION public.temba_update_topupcredits_for_debit();


--
-- Name: msgs_msg temba_when_msgs_update_then_update_topupcredits; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER temba_when_msgs_update_then_update_topupcredits AFTER INSERT OR DELETE OR UPDATE OF topup_id ON public.msgs_msg FOR EACH ROW EXECUTE FUNCTION public.temba_update_topupcredits();


--
-- Name: contacts_contactgroup_contacts when_contact_groups_changed_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER when_contact_groups_changed_then_update_count_trg AFTER INSERT OR DELETE ON public.contacts_contactgroup_contacts FOR EACH ROW EXECUTE FUNCTION public.update_group_count();


--
-- Name: contacts_contact when_contacts_changed_then_update_groups_trg; Type: TRIGGER; Schema: public; Owner: flowartisan
--

CREATE TRIGGER when_contacts_changed_then_update_groups_trg AFTER INSERT OR UPDATE ON public.contacts_contact FOR EACH ROW EXECUTE FUNCTION public.update_contact_system_groups();


--
-- Name: airtime_airtimetransfer airtime_airtimetrans_contact_id_e90a2275_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetrans_contact_id_e90a2275_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_org_id_3eef5867_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_org_id_3eef5867_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_org_id_b1411661_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_apitoken
    ADD CONSTRAINT api_apitoken_org_id_b1411661_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_role_id_391adbf5_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_apitoken
    ADD CONSTRAINT api_apitoken_role_id_391adbf5_fk_auth_group_id FOREIGN KEY (role_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_user_id_9cffaf33_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_apitoken
    ADD CONSTRAINT api_apitoken_user_id_9cffaf33_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_created_by_id_26c82721_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthook
    ADD CONSTRAINT api_resthook_created_by_id_26c82721_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_modified_by_id_d5b8e394_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthook
    ADD CONSTRAINT api_resthook_modified_by_id_d5b8e394_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_org_id_3ac815fe_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthook
    ADD CONSTRAINT api_resthook_org_id_3ac815fe_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_created_by_id_ff38300d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_created_by_id_ff38300d_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_modified_by_id_0e996ea4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_modified_by_id_0e996ea4_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_resthook_id_59cd8bc3_fk_api_resthook_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_resthook_id_59cd8bc3_fk_api_resthook_id FOREIGN KEY (resthook_id) REFERENCES public.api_resthook(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_org_id_2c305947_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_webhookevent
    ADD CONSTRAINT api_webhookevent_org_id_2c305947_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_resthook_id_d2f95048_fk_api_resthook_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.api_webhookevent
    ADD CONSTRAINT api_webhookevent_resthook_id_d2f95048_fk_api_resthook_id FOREIGN KEY (resthook_id) REFERENCES public.api_resthook(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: archives_archive archives_archive_org_id_d19c8f63_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.archives_archive
    ADD CONSTRAINT archives_archive_org_id_d19c8f63_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: archives_archive archives_archive_rollup_id_88538d7b_fk_archives_archive_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.archives_archive
    ADD CONSTRAINT archives_archive_rollup_id_88538d7b_fk_archives_archive_id FOREIGN KEY (rollup_id) REFERENCES public.archives_archive(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: authtoken_token authtoken_token_user_id_35299eff_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_35299eff_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_created_by_id_11fada74_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_created_by_id_11fada74_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_group_id_c1118360_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_group_id_c1118360_fk_contacts_ FOREIGN KEY (group_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_modified_by_id_d578b992_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_modified_by_id_d578b992_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_org_id_ac7ac4ee_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_org_id_ac7ac4ee_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignev_campaign_id_7752d8e7_fk_campaigns; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignev_campaign_id_7752d8e7_fk_campaigns FOREIGN KEY (campaign_id) REFERENCES public.campaigns_campaign(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignev_relative_to_id_f8130023_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignev_relative_to_id_f8130023_fk_contacts_ FOREIGN KEY (relative_to_id) REFERENCES public.contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_created_by_id_7755844d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_created_by_id_7755844d_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_flow_id_7a962066_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_flow_id_7a962066_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_modified_by_id_9645785d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_modified_by_id_9645785d_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_eventfire campaigns_eventfire_contact_id_7d58f0a5_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_contact_id_7d58f0a5_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_eventfire campaigns_eventfire_event_id_f5396422_fk_campaigns; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_event_id_f5396422_fk_campaigns FOREIGN KEY (event_id) REFERENCES public.campaigns_campaignevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_channel_id_1344ae59_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert
    ADD CONSTRAINT channels_alert_channel_id_1344ae59_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_created_by_id_1b7c1310_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert
    ADD CONSTRAINT channels_alert_created_by_id_1b7c1310_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_modified_by_id_e2555348_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert
    ADD CONSTRAINT channels_alert_modified_by_id_e2555348_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_sync_event_id_c866791c_fk_channels_syncevent_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_alert
    ADD CONSTRAINT channels_alert_sync_event_id_c866791c_fk_channels_syncevent_id FOREIGN KEY (sync_event_id) REFERENCES public.channels_syncevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_created_by_id_8141adf4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_created_by_id_8141adf4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_modified_by_id_af6bcc5e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_modified_by_id_af6bcc5e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_org_id_fd34a95a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_org_id_fd34a95a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_parent_id_6e9cc8f5_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channel
    ADD CONSTRAINT channels_channel_parent_id_6e9cc8f5_fk_channels_channel_id FOREIGN KEY (parent_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelconnection channels_channelconn_channel_id_d69daad3_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection
    ADD CONSTRAINT channels_channelconn_channel_id_d69daad3_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelconnection channels_channelconn_contact_id_fe6e9aa5_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection
    ADD CONSTRAINT channels_channelconn_contact_id_fe6e9aa5_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelconnection channels_channelconn_contact_urn_id_b28c1c6d_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection
    ADD CONSTRAINT channels_channelconn_contact_urn_id_b28c1c6d_fk_contacts_ FOREIGN KEY (contact_urn_id) REFERENCES public.contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelconnection channels_channelconnection_org_id_585658cf_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelconnection
    ADD CONSTRAINT channels_channelconnection_org_id_585658cf_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelcount channels_channelcoun_channel_id_b996d6ab_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelcount
    ADD CONSTRAINT channels_channelcoun_channel_id_b996d6ab_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channeleven_channel_id_ba42cee7_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent
    ADD CONSTRAINT channels_channeleven_channel_id_ba42cee7_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channeleven_contact_id_054a8a49_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent
    ADD CONSTRAINT channels_channeleven_contact_id_054a8a49_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channeleven_contact_urn_id_0d28570b_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent
    ADD CONSTRAINT channels_channeleven_contact_urn_id_0d28570b_fk_contacts_ FOREIGN KEY (contact_urn_id) REFERENCES public.contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channelevent_org_id_4d7fff63_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channelevent
    ADD CONSTRAINT channels_channelevent_org_id_4d7fff63_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_channellog_channel_id_567d1602_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channellog
    ADD CONSTRAINT channels_channellog_channel_id_567d1602_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_channellog_connection_id_2609da75_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channellog
    ADD CONSTRAINT channels_channellog_connection_id_2609da75_fk_channels_ FOREIGN KEY (connection_id) REFERENCES public.channels_channelconnection(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_channellog_msg_id_e40e6612_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_channellog
    ADD CONSTRAINT channels_channellog_msg_id_e40e6612_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES public.msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_channel_id_4b72a0f3_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_syncevent
    ADD CONSTRAINT channels_syncevent_channel_id_4b72a0f3_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_created_by_id_1f26df72_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_syncevent
    ADD CONSTRAINT channels_syncevent_created_by_id_1f26df72_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_modified_by_id_3d34e239_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.channels_syncevent
    ADD CONSTRAINT channels_syncevent_modified_by_id_3d34e239_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: classifiers_classifier classifiers_classifier_created_by_id_70c864b9_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier
    ADD CONSTRAINT classifiers_classifier_created_by_id_70c864b9_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: classifiers_classifier classifiers_classifier_modified_by_id_8adf4397_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier
    ADD CONSTRAINT classifiers_classifier_modified_by_id_8adf4397_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: classifiers_classifier classifiers_classifier_org_id_0cffa81e_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_classifier
    ADD CONSTRAINT classifiers_classifier_org_id_0cffa81e_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: classifiers_intent classifiers_intent_classifier_id_4be65c6f_fk_classifie; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.classifiers_intent
    ADD CONSTRAINT classifiers_intent_classifier_id_4be65c6f_fk_classifie FOREIGN KEY (classifier_id) REFERENCES public.classifiers_classifier(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_created_by_id_57537352_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_created_by_id_57537352_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_current_flow_id_4433e731_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_current_flow_id_4433e731_fk_flows_flow_id FOREIGN KEY (current_flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_modified_by_id_db5cbe12_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_modified_by_id_db5cbe12_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_org_id_01d86aa4_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contact
    ADD CONSTRAINT contacts_contact_org_id_01d86aa4_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_created_by_id_7bce7fd0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_created_by_id_7bce7fd0_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_modified_by_id_99cfac9b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_modified_by_id_99cfac9b_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_org_id_d83cc86a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_org_id_d83cc86a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_contacts contacts_contactgrou_contact_id_572f6e61_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgrou_contact_id_572f6e61_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_query_fields contacts_contactgrou_contactfield_id_4e8430b1_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgrou_contactfield_id_4e8430b1_fk_contacts_ FOREIGN KEY (contactfield_id) REFERENCES public.contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_contacts contacts_contactgrou_contactgroup_id_4366e864_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgrou_contactgroup_id_4366e864_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_query_fields contacts_contactgrou_contactgroup_id_94f3146d_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgrou_contactgroup_id_94f3146d_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroupcount contacts_contactgrou_group_id_efcdb311_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroupcount
    ADD CONSTRAINT contacts_contactgrou_group_id_efcdb311_fk_contacts_ FOREIGN KEY (group_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_created_by_id_6bbeef89_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_created_by_id_6bbeef89_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_modified_by_id_a765a76e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_modified_by_id_a765a76e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_org_id_be850815_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_org_id_be850815_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactimportbatch contacts_contactimpo_contact_import_id_f863caf7_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimportbatch
    ADD CONSTRAINT contacts_contactimpo_contact_import_id_f863caf7_fk_contacts_ FOREIGN KEY (contact_import_id) REFERENCES public.contacts_contactimport(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactimport contacts_contactimpo_group_id_4e75f45f_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport
    ADD CONSTRAINT contacts_contactimpo_group_id_4e75f45f_fk_contacts_ FOREIGN KEY (group_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactimport contacts_contactimport_created_by_id_a34024c3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport
    ADD CONSTRAINT contacts_contactimport_created_by_id_a34024c3_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactimport contacts_contactimport_modified_by_id_6cf6a8d5_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport
    ADD CONSTRAINT contacts_contactimport_modified_by_id_6cf6a8d5_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactimport contacts_contactimport_org_id_b7820a48_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contactimport
    ADD CONSTRAINT contacts_contactimport_org_id_b7820a48_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_channel_id_c3a417df_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_channel_id_c3a417df_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_contact_id_ae38055c_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_contact_id_ae38055c_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_org_id_3cc60a3a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_org_id_3cc60a3a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask_group_memberships contacts_exportconta_contactgroup_id_ce69ae43_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask_group_memberships
    ADD CONSTRAINT contacts_exportconta_contactgroup_id_ce69ae43_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportconta_created_by_id_c2721c08_fk_auth_user; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportconta_created_by_id_c2721c08_fk_auth_user FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask_group_memberships contacts_exportconta_exportcontactstask_i_130a97d6_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask_group_memberships
    ADD CONSTRAINT contacts_exportconta_exportcontactstask_i_130a97d6_fk_contacts_ FOREIGN KEY (exportcontactstask_id) REFERENCES public.contacts_exportcontactstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportconta_group_id_f623b2c1_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportconta_group_id_f623b2c1_fk_contacts_ FOREIGN KEY (group_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportconta_modified_by_id_212a480d_fk_auth_user; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportconta_modified_by_id_212a480d_fk_auth_user FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_org_id_07dc65f7_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_org_id_07dc65f7_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: csv_imports_importtask csv_imports_importtask_created_by_id_9657a45f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_created_by_id_9657a45f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: csv_imports_importtask csv_imports_importtask_modified_by_id_282ce6c3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_modified_by_id_282ce6c3_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresu_created_by_id_43d8e1bd_fk_auth_user; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresu_created_by_id_43d8e1bd_fk_auth_user FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresu_exportflowresultstas_8d280d67_fk_flows_exp; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresu_exportflowresultstas_8d280d67_fk_flows_exp FOREIGN KEY (exportflowresultstask_id) REFERENCES public.flows_exportflowresultstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresu_flow_id_b4c9e790_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresu_flow_id_b4c9e790_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresu_modified_by_id_f4871075_fk_auth_user; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresu_modified_by_id_f4871075_fk_auth_user FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_org_id_3a816787_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_org_id_3a816787_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_channel_dependencies flows_flow_channel_d_channel_id_14006e38_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_channel_dependencies
    ADD CONSTRAINT flows_flow_channel_d_channel_id_14006e38_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_channel_dependencies flows_flow_channel_d_flow_id_764a1db2_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_channel_dependencies
    ADD CONSTRAINT flows_flow_channel_d_flow_id_764a1db2_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_classifier_dependencies flows_flow_classifie_classifier_id_ff112811_fk_classifie; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_classifier_dependencies
    ADD CONSTRAINT flows_flow_classifie_classifier_id_ff112811_fk_classifie FOREIGN KEY (classifier_id) REFERENCES public.classifiers_classifier(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_classifier_dependencies flows_flow_classifie_flow_id_dfb6765f_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_classifier_dependencies
    ADD CONSTRAINT flows_flow_classifie_flow_id_dfb6765f_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_created_by_id_2e1adcb6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_created_by_id_2e1adcb6_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_field_dependencies flows_flow_field_dep_contactfield_id_c8b161eb_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_field_dependencies
    ADD CONSTRAINT flows_flow_field_dep_contactfield_id_c8b161eb_fk_contacts_ FOREIGN KEY (contactfield_id) REFERENCES public.contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_field_dependencies flows_flow_field_dependencies_flow_id_ee6ccf51_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_field_dependencies
    ADD CONSTRAINT flows_flow_field_dependencies_flow_id_ee6ccf51_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_flow_dependencies flows_flow_flow_depe_from_flow_id_bee265be_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_flow_dependencies
    ADD CONSTRAINT flows_flow_flow_depe_from_flow_id_bee265be_fk_flows_flo FOREIGN KEY (from_flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_flow_dependencies flows_flow_flow_depe_to_flow_id_015ac795_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_flow_dependencies
    ADD CONSTRAINT flows_flow_flow_depe_to_flow_id_015ac795_fk_flows_flo FOREIGN KEY (to_flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_global_dependencies flows_flow_global_de_flow_id_e4988650_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_global_dependencies
    ADD CONSTRAINT flows_flow_global_de_flow_id_e4988650_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_global_dependencies flows_flow_global_de_global_id_7b0fb9cf_fk_globals_g; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_global_dependencies
    ADD CONSTRAINT flows_flow_global_de_global_id_7b0fb9cf_fk_globals_g FOREIGN KEY (global_id) REFERENCES public.globals_global(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_group_dependencies flows_flow_group_dep_contactgroup_id_f00562b0_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_group_dependencies
    ADD CONSTRAINT flows_flow_group_dep_contactgroup_id_f00562b0_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_group_dependencies flows_flow_group_dependencies_flow_id_de38b8ae_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_group_dependencies
    ADD CONSTRAINT flows_flow_group_dependencies_flow_id_de38b8ae_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_label_dependencies flows_flow_label_dep_label_id_6828c670_fk_msgs_labe; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_label_dependencies
    ADD CONSTRAINT flows_flow_label_dep_label_id_6828c670_fk_msgs_labe FOREIGN KEY (label_id) REFERENCES public.msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_label_dependencies flows_flow_label_dependencies_flow_id_7e6aa4fb_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_label_dependencies
    ADD CONSTRAINT flows_flow_label_dependencies_flow_id_7e6aa4fb_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_labels flows_flow_labels_flow_id_b5b2fc3c_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_b5b2fc3c_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_labels flows_flow_labels_flowlabel_id_ce11c90a_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flowlabel_id_ce11c90a_fk_flows_flowlabel_id FOREIGN KEY (flowlabel_id) REFERENCES public.flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_modified_by_id_493fb4b1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_modified_by_id_493fb4b1_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_org_id_51b9c589_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_org_id_51b9c589_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_saved_by_id_edb563b6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow
    ADD CONSTRAINT flows_flow_saved_by_id_edb563b6_fk_auth_user_id FOREIGN KEY (saved_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_template_dependencies flows_flow_template__flow_id_57119aea_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_template_dependencies
    ADD CONSTRAINT flows_flow_template__flow_id_57119aea_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_template_dependencies flows_flow_template__template_id_0bc5b230_fk_templates; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_template_dependencies
    ADD CONSTRAINT flows_flow_template__template_id_0bc5b230_fk_templates FOREIGN KEY (template_id) REFERENCES public.templates_template(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_ticketer_dependencies flows_flow_ticketer__flow_id_2da8a431_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_ticketer_dependencies
    ADD CONSTRAINT flows_flow_ticketer__flow_id_2da8a431_fk_flows_flo FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_ticketer_dependencies flows_flow_ticketer__ticketer_id_359d030e_fk_tickets_t; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_ticketer_dependencies
    ADD CONSTRAINT flows_flow_ticketer__ticketer_id_359d030e_fk_tickets_t FOREIGN KEY (ticketer_id) REFERENCES public.tickets_ticketer(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_topic_dependencies flows_flow_topic_dep_topic_id_51eebe46_fk_tickets_t; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_topic_dependencies
    ADD CONSTRAINT flows_flow_topic_dep_topic_id_51eebe46_fk_tickets_t FOREIGN KEY (topic_id) REFERENCES public.tickets_topic(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_topic_dependencies flows_flow_topic_dependencies_flow_id_016caef9_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_topic_dependencies
    ADD CONSTRAINT flows_flow_topic_dependencies_flow_id_016caef9_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_user_dependencies flows_flow_user_dependencies_flow_id_0e0ee262_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_user_dependencies
    ADD CONSTRAINT flows_flow_user_dependencies_flow_id_0e0ee262_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_user_dependencies flows_flow_user_dependencies_user_id_9201056c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flow_user_dependencies
    ADD CONSTRAINT flows_flow_user_dependencies_user_id_9201056c_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowcategorycount flows_flowcategorycount_flow_id_ae033ba6_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowcategorycount
    ADD CONSTRAINT flows_flowcategorycount_flow_id_ae033ba6_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_created_by_id_9a7b3325_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_created_by_id_9a7b3325_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_modified_by_id_84e574e7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_modified_by_id_84e574e7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_org_id_4ed2f553_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_org_id_4ed2f553_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_parent_id_73c0a2dd_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_parent_id_73c0a2dd_fk_flows_flowlabel_id FOREIGN KEY (parent_id) REFERENCES public.flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flownodecount flows_flownodecount_flow_id_ba7a0620_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flownodecount
    ADD CONSTRAINT flows_flownodecount_flow_id_ba7a0620_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowpathcount flows_flowpathcount_flow_id_09a7db20_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowpathcount
    ADD CONSTRAINT flows_flowpathcount_flow_id_09a7db20_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_created_by_id_fb31d40f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_created_by_id_fb31d40f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_flow_id_4ae332c8_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_flow_id_4ae332c8_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_modified_by_id_b5464873_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_modified_by_id_b5464873_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_contact_id_985792a9_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_contact_id_985792a9_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_flow_id_9cbb3a32_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_flow_id_9cbb3a32_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_org_id_07d5f694_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_org_id_07d5f694_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_session_id_ef240528_fk_flows_flowsession_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_session_id_ef240528_fk_flows_flowsession_id FOREIGN KEY (session_id) REFERENCES public.flows_flowsession(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_start_id_6f5f00b9_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_start_id_6f5f00b9_fk_flows_flowstart_id FOREIGN KEY (start_id) REFERENCES public.flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_submitted_by_id_573c1038_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowrun
    ADD CONSTRAINT flows_flowrun_submitted_by_id_573c1038_fk_auth_user_id FOREIGN KEY (submitted_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowruncount flows_flowruncount_flow_id_6a87383f_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowruncount
    ADD CONSTRAINT flows_flowruncount_flow_id_6a87383f_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowsession flows_flowsession_connection_id_6fd4e015_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_connection_id_6fd4e015_fk_channels_ FOREIGN KEY (connection_id) REFERENCES public.channels_channelconnection(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowsession flows_flowsession_contact_id_290da86f_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_contact_id_290da86f_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowsession flows_flowsession_current_flow_id_4e32c60b_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_current_flow_id_4e32c60b_fk_flows_flow_id FOREIGN KEY (current_flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowsession flows_flowsession_org_id_9785ea64_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowsession
    ADD CONSTRAINT flows_flowsession_org_id_9785ea64_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_campaign_event_id_70ae0d00_fk_campaigns; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_campaign_event_id_70ae0d00_fk_campaigns FOREIGN KEY (campaign_event_id) REFERENCES public.campaigns_campaignevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_connections flows_flowstart_conn_channelconnection_id_f97be856_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_connections
    ADD CONSTRAINT flows_flowstart_conn_channelconnection_id_f97be856_fk_channels_ FOREIGN KEY (channelconnection_id) REFERENCES public.channels_channelconnection(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_connections flows_flowstart_conn_flowstart_id_f8ef00d6_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_connections
    ADD CONSTRAINT flows_flowstart_conn_flowstart_id_f8ef00d6_fk_flows_flo FOREIGN KEY (flowstart_id) REFERENCES public.flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_contacts flows_flowstart_cont_contact_id_82879510_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_cont_contact_id_82879510_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_contacts flows_flowstart_cont_flowstart_id_d8b4cf8f_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_cont_flowstart_id_d8b4cf8f_fk_flows_flo FOREIGN KEY (flowstart_id) REFERENCES public.flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_created_by_id_4eb88868_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_created_by_id_4eb88868_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_flow_id_c74e7d30_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_flow_id_c74e7d30_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_groups flows_flowstart_grou_contactgroup_id_e2252838_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_grou_contactgroup_id_e2252838_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_groups flows_flowstart_grou_flowstart_id_b44aad1f_fk_flows_flo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_grou_flowstart_id_b44aad1f_fk_flows_flo FOREIGN KEY (flowstart_id) REFERENCES public.flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_org_id_d5383c58_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstart
    ADD CONSTRAINT flows_flowstart_org_id_d5383c58_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstartcount flows_flowstartcount_start_id_a149293f_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.flows_flowstartcount
    ADD CONSTRAINT flows_flowstartcount_start_id_a149293f_fk_flows_flowstart_id FOREIGN KEY (start_id) REFERENCES public.flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: globals_global globals_global_created_by_id_e948d660_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global
    ADD CONSTRAINT globals_global_created_by_id_e948d660_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: globals_global globals_global_modified_by_id_dca008ea_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global
    ADD CONSTRAINT globals_global_modified_by_id_dca008ea_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: globals_global globals_global_org_id_aa26748d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.globals_global
    ADD CONSTRAINT globals_global_org_id_aa26748d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_adminboundary locations_adminbound_parent_id_03a6640e_fk_locations; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_adminboundary
    ADD CONSTRAINT locations_adminbound_parent_id_03a6640e_fk_locations FOREIGN KEY (parent_id) REFERENCES public.locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryal_boundary_id_7ba2d352_fk_locations; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias
    ADD CONSTRAINT locations_boundaryal_boundary_id_7ba2d352_fk_locations FOREIGN KEY (boundary_id) REFERENCES public.locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_created_by_id_46911c69_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_created_by_id_46911c69_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_modified_by_id_fabf1a13_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_modified_by_id_fabf1a13_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_org_id_930a8491_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_org_id_930a8491_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_channel_id_896f7d11_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_channel_id_896f7d11_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_contacts msgs_broadcast_conta_broadcast_id_c5dc5132_fk_msgs_broa; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_conta_broadcast_id_c5dc5132_fk_msgs_broa FOREIGN KEY (broadcast_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_contacts msgs_broadcast_conta_contact_id_9ffd3873_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_conta_contact_id_9ffd3873_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_created_by_id_bc4d5bb1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_created_by_id_bc4d5bb1_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_groups msgs_broadcast_group_broadcast_id_1b1d150a_fk_msgs_broa; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_group_broadcast_id_1b1d150a_fk_msgs_broa FOREIGN KEY (broadcast_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_groups msgs_broadcast_group_contactgroup_id_c8187bee_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_group_contactgroup_id_c8187bee_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_modified_by_id_b51c67df_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_modified_by_id_b51c67df_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_org_id_78c94f15_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_org_id_78c94f15_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_parent_id_a2f08782_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_parent_id_a2f08782_fk_msgs_broadcast_id FOREIGN KEY (parent_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_schedule_id_3bb038fe_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_3bb038fe_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES public.schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_ticket_id_85a185ac_fk_tickets_ticket_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_ticket_id_85a185ac_fk_tickets_ticket_id FOREIGN KEY (ticket_id) REFERENCES public.tickets_ticket(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_broadcast_id_aaf9d7b9_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_aaf9d7b9_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_contacturn_id_9fe60d63_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_contacturn_id_9fe60d63_fk_contacts_ FOREIGN KEY (contacturn_id) REFERENCES public.contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcastmsgcount msgs_broadcastmsgcou_broadcast_id_893c7af4_fk_msgs_broa; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_broadcastmsgcount
    ADD CONSTRAINT msgs_broadcastmsgcou_broadcast_id_893c7af4_fk_msgs_broa FOREIGN KEY (broadcast_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagest_contactgroup_id_3b816325_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagest_contactgroup_id_3b816325_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagest_exportmessagestask_i_3071019e_fk_msgs_expo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagest_exportmessagestask_i_3071019e_fk_msgs_expo FOREIGN KEY (exportmessagestask_id) REFERENCES public.msgs_exportmessagestask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_created_by_id_f3b48148_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_created_by_id_f3b48148_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_label_id_80585f7d_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_label_id_80585f7d_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES public.msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_modified_by_id_d76b3bdf_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_modified_by_id_d76b3bdf_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_org_id_8b5afdca_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_org_id_8b5afdca_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_created_by_id_59cd46ee_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_created_by_id_59cd46ee_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_folder_id_fef43746_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_folder_id_fef43746_fk_msgs_label_id FOREIGN KEY (folder_id) REFERENCES public.msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_modified_by_id_8a4d5291_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_modified_by_id_8a4d5291_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_org_id_a63db233_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_label
    ADD CONSTRAINT msgs_label_org_id_a63db233_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_labelcount msgs_labelcount_label_id_3d012b42_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_labelcount
    ADD CONSTRAINT msgs_labelcount_label_id_3d012b42_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES public.msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_broadcast_id_7514e534_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_broadcast_id_7514e534_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES public.msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_channel_id_0592b6b0_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_channel_id_0592b6b0_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_contact_id_5a7d63da_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_contact_id_5a7d63da_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_contact_urn_id_fc1da718_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_contact_urn_id_fc1da718_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES public.contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_flow_id_5f9563e5_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_flow_id_5f9563e5_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels msgs_msg_labels_label_id_525dfbc1_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_label_id_525dfbc1_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES public.msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels msgs_msg_labels_msg_id_a1f8fefa_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_a1f8fefa_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES public.msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_org_id_d3488a20_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_org_id_d3488a20_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_topup_id_0d2ccb2d_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_msg
    ADD CONSTRAINT msgs_msg_topup_id_0d2ccb2d_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES public.orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_systemlabelcount msgs_systemlabelcount_org_id_fed550a8_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.msgs_systemlabelcount
    ADD CONSTRAINT msgs_systemlabelcount_org_id_fed550a8_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_incident notifications_incide_channel_id_52f252c5_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_incident
    ADD CONSTRAINT notifications_incide_channel_id_52f252c5_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_incident notifications_incident_org_id_b5cb2702_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_incident
    ADD CONSTRAINT notifications_incident_org_id_b5cb2702_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notifi_contact_export_id_f8a32d90_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notifi_contact_export_id_f8a32d90_fk_contacts_ FOREIGN KEY (contact_export_id) REFERENCES public.contacts_exportcontactstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notifi_contact_import_id_93e583b6_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notifi_contact_import_id_93e583b6_fk_contacts_ FOREIGN KEY (contact_import_id) REFERENCES public.contacts_contactimport(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notifi_incident_id_f5d6cdb9_fk_notificat; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notifi_incident_id_f5d6cdb9_fk_notificat FOREIGN KEY (incident_id) REFERENCES public.notifications_incident(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notifi_message_export_id_1fb6515c_fk_msgs_expo; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notifi_message_export_id_1fb6515c_fk_msgs_expo FOREIGN KEY (message_export_id) REFERENCES public.msgs_exportmessagestask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notifi_results_export_id_30213b45_fk_flows_exp; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notifi_results_export_id_30213b45_fk_flows_exp FOREIGN KEY (results_export_id) REFERENCES public.flows_exportflowresultstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notificationcount notifications_notifi_user_id_4aca02ba_fk_auth_user; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notificationcount
    ADD CONSTRAINT notifications_notifi_user_id_4aca02ba_fk_auth_user FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notification_org_id_b4c202e9_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notification_org_id_b4c202e9_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notification notifications_notification_user_id_b5e8c0ff_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notification
    ADD CONSTRAINT notifications_notification_user_id_b5e8c0ff_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: notifications_notificationcount notifications_notificationcount_org_id_50b11add_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.notifications_notificationcount
    ADD CONSTRAINT notifications_notificationcount_org_id_50b11add_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_backuptoken orgs_backuptoken_user_id_2e881bc5_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_backuptoken
    ADD CONSTRAINT orgs_backuptoken_user_id_2e881bc5_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_created_by_id_902a99c9_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_created_by_id_902a99c9_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_modified_by_id_a7b1b154_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_modified_by_id_a7b1b154_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_org_id_f6caae69_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_org_id_f6caae69_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_beneficiary_id_b95fb2b4_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_debit
    ADD CONSTRAINT orgs_debit_beneficiary_id_b95fb2b4_fk_orgs_topup_id FOREIGN KEY (beneficiary_id) REFERENCES public.orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_created_by_id_6e727579_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_debit
    ADD CONSTRAINT orgs_debit_created_by_id_6e727579_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_topup_id_be941fdc_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_debit
    ADD CONSTRAINT orgs_debit_topup_id_be941fdc_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES public.orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_created_by_id_147e359a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation
    ADD CONSTRAINT orgs_invitation_created_by_id_147e359a_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_modified_by_id_dd8cae65_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation
    ADD CONSTRAINT orgs_invitation_modified_by_id_dd8cae65_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_org_id_d9d2be95_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_invitation
    ADD CONSTRAINT orgs_invitation_org_id_d9d2be95_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrators orgs_org_administrators_org_id_df1333f0_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_df1333f0_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrators orgs_org_administrators_user_id_74fbbbcb_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_user_id_74fbbbcb_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_agents orgs_org_agents_org_id_009f15fa_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_agents
    ADD CONSTRAINT orgs_org_agents_org_id_009f15fa_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_agents orgs_org_agents_user_id_1626becb_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_agents
    ADD CONSTRAINT orgs_org_agents_user_id_1626becb_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_country_id_c6e479af_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_country_id_c6e479af_fk_locations_adminboundary_id FOREIGN KEY (country_id) REFERENCES public.locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_created_by_id_f738c068_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_created_by_id_f738c068_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors orgs_org_editors_org_id_2ac53adb_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_2ac53adb_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors orgs_org_editors_user_id_21fb7e08_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_user_id_21fb7e08_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_modified_by_id_61e424e7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_modified_by_id_61e424e7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_parent_id_79ba1bbf_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org
    ADD CONSTRAINT orgs_org_parent_id_79ba1bbf_fk_orgs_org_id FOREIGN KEY (parent_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_surveyors orgs_org_surveyors_org_id_80c50287_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_org_id_80c50287_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_surveyors orgs_org_surveyors_user_id_78800efa_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_user_id_78800efa_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers orgs_org_viewers_org_id_d7604492_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_d7604492_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers orgs_org_viewers_user_id_0650bd4d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_user_id_0650bd4d_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_orgactivity orgs_orgactivity_org_id_1596e05b_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgactivity
    ADD CONSTRAINT orgs_orgactivity_org_id_1596e05b_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_orgmembership orgs_orgmembership_org_id_35cc8172_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgmembership
    ADD CONSTRAINT orgs_orgmembership_org_id_35cc8172_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_orgmembership orgs_orgmembership_user_id_ebcaadcf_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_orgmembership
    ADD CONSTRAINT orgs_orgmembership_user_id_ebcaadcf_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_created_by_id_026008e4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topup
    ADD CONSTRAINT orgs_topup_created_by_id_026008e4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_modified_by_id_c6b91b30_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topup
    ADD CONSTRAINT orgs_topup_modified_by_id_c6b91b30_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_org_id_cde450ed_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topup
    ADD CONSTRAINT orgs_topup_org_id_cde450ed_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topupcredits orgs_topupcredits_topup_id_9b2e5f7d_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_topupcredits
    ADD CONSTRAINT orgs_topupcredits_topup_id_9b2e5f7d_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES public.orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_usersettings orgs_usersettings_team_id_cf1e2965_fk_tickets_team_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_team_id_cf1e2965_fk_tickets_team_id FOREIGN KEY (team_id) REFERENCES public.tickets_team(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_usersettings orgs_usersettings_user_id_ef7b03af_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_user_id_ef7b03af_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: policies_consent policies_consent_policy_id_cf6ba8c2_fk_policies_policy_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_consent
    ADD CONSTRAINT policies_consent_policy_id_cf6ba8c2_fk_policies_policy_id FOREIGN KEY (policy_id) REFERENCES public.policies_policy(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: policies_consent policies_consent_user_id_ae612331_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_consent
    ADD CONSTRAINT policies_consent_user_id_ae612331_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: policies_policy policies_policy_created_by_id_3e6781aa_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_policy
    ADD CONSTRAINT policies_policy_created_by_id_3e6781aa_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: policies_policy policies_policy_modified_by_id_67fe46ae_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.policies_policy
    ADD CONSTRAINT policies_policy_modified_by_id_67fe46ae_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead public_lead_created_by_id_2da6cfc7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_lead
    ADD CONSTRAINT public_lead_created_by_id_2da6cfc7_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead public_lead_modified_by_id_934f2f0c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_lead
    ADD CONSTRAINT public_lead_modified_by_id_934f2f0c_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video public_video_created_by_id_11455096_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_video
    ADD CONSTRAINT public_video_created_by_id_11455096_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video public_video_modified_by_id_7009d0a7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.public_video
    ADD CONSTRAINT public_video_modified_by_id_7009d0a7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_airtime_transfer_id_4fc31c64_fk_airtime_a; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_airtime_transfer_id_4fc31c64_fk_airtime_a FOREIGN KEY (airtime_transfer_id) REFERENCES public.airtime_airtimetransfer(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_channel_id_551e481b_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_channel_id_551e481b_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_classifier_id_a49b0f1a_fk_classifie; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_classifier_id_a49b0f1a_fk_classifie FOREIGN KEY (classifier_id) REFERENCES public.classifiers_classifier(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_flow_id_0694ff8c_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_flow_id_0694ff8c_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_org_id_2ad1fbae_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_org_id_2ad1fbae_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: request_logs_httplog request_logs_httplog_ticketer_id_7b690d67_fk_tickets_t; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.request_logs_httplog
    ADD CONSTRAINT request_logs_httplog_ticketer_id_7b690d67_fk_tickets_t FOREIGN KEY (ticketer_id) REFERENCES public.tickets_ticketer(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedule schedules_schedule_created_by_id_7a808dd9_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.schedules_schedule
    ADD CONSTRAINT schedules_schedule_created_by_id_7a808dd9_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedule schedules_schedule_modified_by_id_75f3d89a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.schedules_schedule
    ADD CONSTRAINT schedules_schedule_modified_by_id_75f3d89a_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedule schedules_schedule_org_id_bb6269db_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.schedules_schedule
    ADD CONSTRAINT schedules_schedule_org_id_bb6269db_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: templates_template templates_template_org_id_01fb381e_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_template
    ADD CONSTRAINT templates_template_org_id_01fb381e_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: templates_templatetranslation templates_templatetr_channel_id_07917e3a_fk_channels_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_templatetranslation
    ADD CONSTRAINT templates_templatetr_channel_id_07917e3a_fk_channels_ FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: templates_templatetranslation templates_templatetr_template_id_66a162f6_fk_templates; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.templates_templatetranslation
    ADD CONSTRAINT templates_templatetr_template_id_66a162f6_fk_templates FOREIGN KEY (template_id) REFERENCES public.templates_template(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_team tickets_team_created_by_id_6e92ba12_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team
    ADD CONSTRAINT tickets_team_created_by_id_6e92ba12_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_team tickets_team_modified_by_id_99a64cad_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team
    ADD CONSTRAINT tickets_team_modified_by_id_99a64cad_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_team tickets_team_org_id_2a011111_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team
    ADD CONSTRAINT tickets_team_org_id_2a011111_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_team_topics tickets_team_topics_team_id_ea473ed0_fk_tickets_team_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team_topics
    ADD CONSTRAINT tickets_team_topics_team_id_ea473ed0_fk_tickets_team_id FOREIGN KEY (team_id) REFERENCES public.tickets_team(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_team_topics tickets_team_topics_topic_id_7c317c54_fk_tickets_topic_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_team_topics
    ADD CONSTRAINT tickets_team_topics_topic_id_7c317c54_fk_tickets_topic_id FOREIGN KEY (topic_id) REFERENCES public.tickets_topic(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticket tickets_ticket_assignee_id_3a5aa407_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_assignee_id_3a5aa407_fk_auth_user_id FOREIGN KEY (assignee_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticket tickets_ticket_contact_id_a9a8a57d_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_contact_id_a9a8a57d_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticket tickets_ticket_org_id_56b25ecf_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_org_id_56b25ecf_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticket tickets_ticket_ticketer_id_0c8d390f_fk_tickets_ticketer_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_ticketer_id_0c8d390f_fk_tickets_ticketer_id FOREIGN KEY (ticketer_id) REFERENCES public.tickets_ticketer(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticket tickets_ticket_topic_id_80564e0d_fk_tickets_topic_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticket
    ADD CONSTRAINT tickets_ticket_topic_id_80564e0d_fk_tickets_topic_id FOREIGN KEY (topic_id) REFERENCES public.tickets_topic(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketcount tickets_ticketcount_assignee_id_94b9a29c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketcount
    ADD CONSTRAINT tickets_ticketcount_assignee_id_94b9a29c_fk_auth_user_id FOREIGN KEY (assignee_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketcount tickets_ticketcount_org_id_45a131d2_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketcount
    ADD CONSTRAINT tickets_ticketcount_org_id_45a131d2_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketer tickets_ticketer_created_by_id_65853966_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer
    ADD CONSTRAINT tickets_ticketer_created_by_id_65853966_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketer tickets_ticketer_modified_by_id_41ab9a7e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer
    ADD CONSTRAINT tickets_ticketer_modified_by_id_41ab9a7e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketer tickets_ticketer_org_id_00771428_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketer
    ADD CONSTRAINT tickets_ticketer_org_id_00771428_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_assignee_id_5b6836f3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_assignee_id_5b6836f3_fk_auth_user_id FOREIGN KEY (assignee_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_contact_id_a5104bc7_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_contact_id_a5104bc7_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_created_by_id_1dd8436d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_created_by_id_1dd8436d_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_org_id_58f88b39_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_org_id_58f88b39_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_ticket_id_b572d14b_fk_tickets_ticket_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_ticket_id_b572d14b_fk_tickets_ticket_id FOREIGN KEY (ticket_id) REFERENCES public.tickets_ticket(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_ticketevent tickets_ticketevent_topic_id_ce719f3b_fk_tickets_topic_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_ticketevent
    ADD CONSTRAINT tickets_ticketevent_topic_id_ce719f3b_fk_tickets_topic_id FOREIGN KEY (topic_id) REFERENCES public.tickets_topic(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_topic tickets_topic_created_by_id_a7daf971_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic
    ADD CONSTRAINT tickets_topic_created_by_id_a7daf971_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_topic tickets_topic_modified_by_id_409a6eb0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic
    ADD CONSTRAINT tickets_topic_modified_by_id_409a6eb0_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tickets_topic tickets_topic_org_id_0b22bd8a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.tickets_topic
    ADD CONSTRAINT tickets_topic_org_id_0b22bd8a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_channel_id_1e8206f8_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_channel_id_1e8206f8_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES public.channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_contacts triggers_trigger_con_contact_id_58bca9a4_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_con_contact_id_58bca9a4_fk_contacts_ FOREIGN KEY (contact_id) REFERENCES public.contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_contacts triggers_trigger_con_trigger_id_2d7952cd_fk_triggers_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_con_trigger_id_2d7952cd_fk_triggers_ FOREIGN KEY (trigger_id) REFERENCES public.triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_created_by_id_265631d7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_created_by_id_265631d7_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_exclude_groups triggers_trigger_exc_contactgroup_id_b62cd1da_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_exclude_groups
    ADD CONSTRAINT triggers_trigger_exc_contactgroup_id_b62cd1da_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_exclude_groups triggers_trigger_exc_trigger_id_753d099a_fk_triggers_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_exclude_groups
    ADD CONSTRAINT triggers_trigger_exc_trigger_id_753d099a_fk_triggers_ FOREIGN KEY (trigger_id) REFERENCES public.triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_flow_id_89d39d82_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_flow_id_89d39d82_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES public.flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_groups triggers_trigger_gro_contactgroup_id_648b9858_fk_contacts_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_gro_contactgroup_id_648b9858_fk_contacts_ FOREIGN KEY (contactgroup_id) REFERENCES public.contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_groups triggers_trigger_gro_trigger_id_e3f9e0a9_fk_triggers_; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_gro_trigger_id_e3f9e0a9_fk_triggers_ FOREIGN KEY (trigger_id) REFERENCES public.triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_modified_by_id_6a5f982f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_modified_by_id_6a5f982f_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_org_id_4a23f4c2_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_org_id_4a23f4c2_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES public.orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_schedule_id_22e85233_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_22e85233_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES public.schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_passwordhistory users_passwordhistory_user_id_1396dbb7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_user_id_1396dbb7_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_recoverytoken users_recoverytoken_user_id_0d7bef8c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: flowartisan
--

ALTER TABLE ONLY public.users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_user_id_0d7bef8c_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- PostgreSQL database dump complete
--

