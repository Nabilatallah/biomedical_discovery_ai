-- ============================================================================
-- BioDiscoveryAI Governance Event Streaming
-- Migration: V080__governance_event_streaming.sql
-- Purpose:
--   Govern real-time event streaming from PostgreSQL governance events into
--   Kafka, cloud event buses, SIEM, data lakehouse, dashboards, and partner
--   federation endpoints.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_streaming;

CREATE TABLE IF NOT EXISTS governance_streaming.event_streams (
    event_stream_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_code TEXT NOT NULL UNIQUE,
    stream_name TEXT NOT NULL,
    stream_description TEXT NOT NULL,
    stream_backend TEXT NOT NULL CHECK (stream_backend IN ('kafka','aws_eventbridge','azure_eventgrid','gcp_pubsub','webhook','database_queue','other')),
    destination_uri TEXT NOT NULL,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_streaming.stream_subscriptions (
    stream_subscription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_stream_id UUID NOT NULL REFERENCES governance_streaming.event_streams(event_stream_id),
    subscriber_name TEXT NOT NULL,
    subscriber_type TEXT NOT NULL CHECK (subscriber_type IN ('siem','dashboard','lakehouse','workflow','federation','alerting','other')),
    filter_expression TEXT,
    delivery_mode TEXT NOT NULL DEFAULT 'at_least_once'
        CHECK (delivery_mode IN ('at_least_once','exactly_once','best_effort')),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(event_stream_id, subscriber_name)
);

CREATE TABLE IF NOT EXISTS governance_streaming.event_delivery_logs (
    event_delivery_log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_stream_id UUID NOT NULL REFERENCES governance_streaming.event_streams(event_stream_id),
    source_event_id UUID,
    source_event_hash TEXT,
    delivery_status TEXT NOT NULL CHECK (delivery_status IN ('queued','delivered','failed','retrying','dead_lettered')),
    delivered_at TIMESTAMPTZ,
    retry_count INT NOT NULL DEFAULT 0,
    error_summary TEXT,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_streaming.dead_letter_events (
    dead_letter_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_delivery_log_id UUID NOT NULL REFERENCES governance_streaming.event_delivery_logs(event_delivery_log_id),
    failure_reason TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    remediation_status TEXT NOT NULL DEFAULT 'open'
        CHECK (remediation_status IN ('open','replayed','ignored','resolved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW governance_streaming.v_stream_health AS
SELECT
    es.stream_code,
    es.stream_backend,
    es.approval_status,
    COUNT(edl.event_delivery_log_id) AS delivery_count,
    COUNT(edl.event_delivery_log_id) FILTER (WHERE edl.delivery_status = 'failed') AS failed_count,
    COUNT(edl.event_delivery_log_id) FILTER (WHERE edl.delivery_status = 'dead_lettered') AS dead_letter_count
FROM governance_streaming.event_streams es
LEFT JOIN governance_streaming.event_delivery_logs edl ON edl.event_stream_id = es.event_stream_id
GROUP BY es.stream_code, es.stream_backend, es.approval_status;

COMMIT;
