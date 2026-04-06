--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.1
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: archive; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE archive WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


ALTER DATABASE archive OWNER TO postgres;

\connect archive

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner:
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner:
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: encompass_import_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE encompass_import_data (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    import_source_id uuid,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE encompass_import_data OWNER TO postgres;

--
-- Name: import_source; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE import_source (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    name character varying,
    description text,
    rules jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE import_source OWNER TO postgres;

--
-- Name: realtytrac_avm; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE realtytrac_avm (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rt_property_id character varying(10),
    refi boolean DEFAULT false,
    adjustable boolean DEFAULT false,
    loan_type character varying(30),
    loan_one_type character varying(30),
    loan_two_type character varying(30),
    loan_three_type character varying(30),
    loan_one_adjustable boolean,
    loan_two_adjustable boolean,
    loan_three_adjustable boolean
);


ALTER TABLE realtytrac_avm OWNER TO postgres;

--
-- Name: realtytrac_avm_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE realtytrac_avm_history (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    import_source_id uuid,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rt_property_id character varying(10),
    refi boolean DEFAULT false,
    adjustable boolean DEFAULT false,
    loan_type character varying(30),
    loan_one_type character varying(30),
    loan_two_type character varying(30),
    loan_three_type character varying(30),
    loan_one_adjustable boolean,
    loan_two_adjustable boolean,
    loan_three_adjustable boolean
);


ALTER TABLE realtytrac_avm_history OWNER TO postgres;

--
-- Name: realtytrac_import_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE realtytrac_import_data (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    import_source_id uuid,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    refi boolean DEFAULT false,
    adjustable boolean DEFAULT false,
    loan_type character varying(30),
    loan_one_type character varying(30),
    loan_two_type character varying(30),
    loan_three_type character varying(30),
    loan_one_adjustable boolean,
    loan_two_adjustable boolean,
    loan_three_adjustable boolean,
    rt_property_id character varying(10)
);


ALTER TABLE realtytrac_import_data OWNER TO postgres;

--
-- Name: realtytrac_recorder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE realtytrac_recorder (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    import_source_id uuid,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rt_property_id character varying(10),
    refi boolean DEFAULT false,
    adjustable boolean DEFAULT false,
    loan_type character varying(30),
    loan_one_type character varying(30),
    loan_two_type character varying(30),
    loan_three_type character varying(30),
    loan_one_adjustable boolean,
    loan_two_adjustable boolean,
    loan_three_adjustable boolean
);


ALTER TABLE realtytrac_recorder OWNER TO postgres;

--
-- Name: realtytrac_tax; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE realtytrac_tax (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    fields jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    import_source_id uuid,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rt_property_id character varying(10),
    refi boolean DEFAULT false,
    adjustable boolean DEFAULT false,
    loan_type character varying(30),
    loan_one_type character varying(30),
    loan_two_type character varying(30),
    loan_three_type character varying(30),
    loan_one_adjustable boolean,
    loan_two_adjustable boolean,
    loan_three_adjustable boolean,
    exists_in_elasticsearch boolean DEFAULT false NOT NULL
);


ALTER TABLE realtytrac_tax OWNER TO postgres;

--
-- Name: encompass_import_data encompass_import_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY encompass_import_data
    ADD CONSTRAINT encompass_import_data_pkey PRIMARY KEY (id);


--
-- Name: import_source import_source_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY import_source
    ADD CONSTRAINT import_source_pkey PRIMARY KEY (id);


--
-- Name: realtytrac_import_data realtytrac_import_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY realtytrac_import_data
    ADD CONSTRAINT realtytrac_import_data_pkey PRIMARY KEY (id);


--
-- Name: encompass_import_data_expr_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX encompass_import_data_expr_idx ON encompass_import_data USING btree (((fields -> 'NMLS Loan Originator ID'::text)));


--
-- Name: encompass_import_data_expr_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX encompass_import_data_expr_idx1 ON encompass_import_data USING btree (((fields -> 'Loan Number'::text)));


--
-- Name: encompass_import_data_expr_idx2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX encompass_import_data_expr_idx2 ON encompass_import_data USING btree (((fields -> 'Lender NMLS ID'::text)));


--
-- Name: encompass_import_data_expr_idx3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX encompass_import_data_expr_idx3 ON encompass_import_data USING btree (((fields -> 'Closing Date'::text)));


--
-- Name: encompass_import_data_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "encompass_import_data_created_at_idx" ON "public"."encompass_import_data"("created_at");

--
-- Name: index_import_data_on_fields; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_import_data_on_fields ON realtytrac_import_data USING gin (fields);


--
-- Name: index_import_source_on_description; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_import_source_on_description ON import_source USING btree (description);


--
-- Name: index_import_source_on_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_import_source_on_name ON import_source USING btree (name);


--
-- Name: index_import_source_on_rules; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_import_source_on_rules ON import_source USING gin (rules);


--
-- Name: realtytrac_avm_rt_property_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX realtytrac_avm_rt_property_id_idx ON realtytrac_avm USING btree (rt_property_id);


--
-- Name: realtytrac_recorder_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX realtytrac_recorder_created_at_idx ON realtytrac_recorder USING btree (created_at);


--
-- Name: realtytrac_recorder_rt_property_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX realtytrac_recorder_rt_property_id_idx ON realtytrac_recorder USING btree (rt_property_id);


--
-- Name: realtytrac_tax_rt_property_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX realtytrac_tax_rt_property_id_idx ON realtytrac_tax USING btree (rt_property_id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM postgres;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: plpgsql; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON LANGUAGE plpgsql TO postgres;


--
-- PostgreSQL database dump complete
--
