INSERT INTO registry.owners (owner_id, full_name, role_name, email)
VALUES
('platform_owner','TBD','Platform Owner','tbd@example.com'),
('security_owner','TBD','Security Owner','tbd@example.com'),
('compliance_owner','TBD','Compliance Owner','tbd@example.com'),
('validation_owner','TBD','Validation Owner','tbd@example.com'),
('quality_owner','TBD','Quality Owner','tbd@example.com')
ON CONFLICT (owner_id) DO NOTHING;

INSERT INTO registry.modules (module_id, module_name, lifecycle_status, architectural_layer, owner_ref)
VALUES ('B001','Foundation','Draft','Foundation','platform_owner')
ON CONFLICT (module_id) DO NOTHING;

INSERT INTO registry.scripts (
    script_id, document_id, script_name, module_id, version, lifecycle_status,
    execution_type, entry_point, parent_workflow, purpose, regulated_use,
    part11, security_profile, validation_profile, release_profile, execution_modes
)
VALUES (
'B001_01','DOC-B001-01','Runtime Safety Preflight','B001','1.0.0','Draft',
'Foundation',true,'Nextflow',
'{"business_objective":"Establish runtime safety baseline","technical_objective":"Validate runtime, policy, security, provenance, and evidence","scientific_objective":"Protect reproducibility"}',
'{"gxp_impact":"Indirect","gxp_rationale":"Supports regulated workflow infrastructure"}',
'{"electronic_records":true,"electronic_signatures":false,"audit_trail_required":true,"part11_impact":"Indirect"}',
'{"data_classification":"Internal","secrets_used":false,"privileged_execution":false}',
'{"validation_package":"validation/B001_01","urs":"validation/URS.md","iq":"validation/IQ.md","oq":"validation/OQ.md","pq":"validation/PQ.md","rtm":"validation/RTM.csv"}',
'{"release_id":"REL-2026-0001","container_digest":"sha256:REPLACE_WITH_DIGEST","sbom_reference":"s3://bdai-evidence/sbom/b001.cdx.json"}',
'{"local":"bash script.sh --target local","hpc_direct":"bash script.sh --target hpc","hpc_slurm":"sbatch script.slurm","aws_direct":"bash script.sh --target aws","aws_batch":"nextflow run main.nf -profile aws_batch"}'
)
ON CONFLICT (script_id) DO NOTHING;

INSERT INTO registry.artifact_types (
    artifact_type_id, description, default_storage_location,
    store_body_in_db, retention_period, legal_hold_supported
)
VALUES
('audit_event','Structured audit event','PostgreSQL',true,'7_years',true),
('step_log','Execution step log','PostgreSQL',true,'7_years',true),
('error_log','Error event','PostgreSQL',true,'7_years',true),
('dependency_inventory','Dependency inventory JSONB','PostgreSQL',true,'7_years',true),
('provenance','Provenance JSONB','PostgreSQL',true,'7_years',true),
('compliance_evidence','Compliance evidence JSONB','PostgreSQL',true,'7_years',true),
('validation_result','Validation result','PostgreSQL',true,'7_years',true),
('capa_deviation','CAPA/deviation record','PostgreSQL',true,'7_years',true),
('resource_cost','Resource/cost metric','PostgreSQL',true,'7_years',true),
('artifact_manifest','Artifact manifest metadata','PostgreSQL',true,'7_years',true),
('execution_report_markdown','Execution report markdown','PostgreSQL and rendered file',true,'7_years',true),
('large_report_pdf_html','Large rendered report','S3 Object Lock',false,'7_years',true),
('sbom','SBOM file','S3 Object Lock',false,'7_years',true),
('trivy_report','Trivy scan report','S3 Object Lock plus DB summary',false,'7_years',true),
('nextflow_timeline','Nextflow timeline HTML','S3 Object Lock',false,'7_years',true),
('nextflow_dag','Nextflow DAG HTML','S3 Object Lock',false,'7_years',true),
('raw_log','Raw log stream','Loki/CloudWatch/S3',false,'7_years',true),
('scientific_output','Large scientific output','Object storage/data lake',false,'project_policy',true)
ON CONFLICT (artifact_type_id) DO NOTHING;

INSERT INTO api_contract.evidence_api_contracts (contract_id, version, contract_json, status)
VALUES (
'evidence-api-v1',
'1.0.0',
'{"operations":["create_run","audit_event","step_event","error_event","register_artifact","finalize_run"],"required_fields":["run_id","script_id","module_id","created_at"],"artifact_contract":["storage_uri","sha256","artifact_type","retention_period","legal_hold"]}',
'Controlled'
)
ON CONFLICT (contract_id) DO NOTHING;



-- =============================================================================
-- V11 execution environment registry seeds.
-- These rows make hybrid reproducibility explicit: local, Explorer HPC, AWS Batch,
-- and AWS ECS are first-class governed environments.
-- =============================================================================
INSERT INTO registry.execution_environments (
    environment_id, environment_name, environment_type, scheduler_type,
    container_runtime, cpu_count, memory_gb, gpu_type, gpu_count,
    storage_class, network_policy, cloud_provider, region, hpc_cluster_name,
    queue_or_partition, account_or_project, security_profile, compliance_profile, metadata
)
VALUES
('local-dev','Local Development Workstation','local','none','docker',8,32.00,NULL,0,'local-filesystem','developer-controlled',NULL,NULL,NULL,NULL,NULL,
 '{"secrets":"local env only","network":"developer controlled","container_user":"non-root preferred"}',
 '{"intended_use":"development and dry-run only","gxp_use":"not controlled unless validated"}',
 '{"answerable_questions":["Which runs executed locally?","Which runs used Docker?"]}'),
('explorer-hpc-apptainer','Explorer HPC SLURM + Apptainer','hpc','SLURM','apptainer',32,128.00,NULL,0,'shared-filesystem','restricted-hpc-network',NULL,NULL,'Explorer','standard','biodiscoveryai',
 '{"container":"immutable SIF","root":"not required","scheduler_audit":"SLURM job id captured","network":"restricted or disabled where feasible"}',
 '{"intended_use":"controlled research/HPC execution","gxp_value":"reproducible compute environment traceability"}',
 '{"answerable_questions":["Which runs executed on Explorer HPC?","Which runs used Apptainer?","Which runs used SLURM?"]}'),
('explorer-hpc-gpu-apptainer','Explorer HPC GPU SLURM + Apptainer','hpc','SLURM','apptainer',32,192.00,'NVIDIA GPU',1,'shared-filesystem','restricted-hpc-network',NULL,NULL,'Explorer','gpu','biodiscoveryai',
 '{"container":"immutable GPU-capable SIF","gpu_access":"scheduler controlled","scheduler_audit":"SLURM job id captured"}',
 '{"intended_use":"controlled GPU research/HPC execution","gxp_value":"GPU node traceability"}',
 '{"answerable_questions":["Which runs used GPU nodes?","Which GPU runs used Apptainer?"]}'),
('aws-batch-docker','AWS Batch Docker Managed Compute','aws','AWS Batch','docker',16,64.00,NULL,0,'s3-object-lock','vpc-controlled','aws','us-east-1',NULL,'batch-queue','biodiscoveryai',
 '{"iam":"least privilege","kms":"required","artifact_storage":"S3 Object Lock","logs":"CloudWatch and S3"}',
 '{"intended_use":"controlled cloud batch execution","gxp_value":"managed audit/security/storage traceability"}',
 '{"answerable_questions":["Which runs used AWS Batch?","Which runs used Docker in AWS?"]}'),
('aws-ecs-docker','AWS ECS/Fargate Docker Service Runtime','aws','ECS','docker',4,16.00,NULL,0,'s3-object-lock','vpc-controlled','aws','us-east-1',NULL,'ecs-service','biodiscoveryai',
 '{"iam":"task role least privilege","kms":"required","logs":"CloudWatch","secrets":"Secrets Manager"}',
 '{"intended_use":"service/API runtime","gxp_value":"managed service runtime traceability"}',
 '{"answerable_questions":["Which runs used ECS?","Which runs used Docker?"]}')
ON CONFLICT (environment_id) DO UPDATE SET
    environment_name=EXCLUDED.environment_name,
    environment_type=EXCLUDED.environment_type,
    scheduler_type=EXCLUDED.scheduler_type,
    container_runtime=EXCLUDED.container_runtime,
    cpu_count=EXCLUDED.cpu_count,
    memory_gb=EXCLUDED.memory_gb,
    gpu_type=EXCLUDED.gpu_type,
    gpu_count=EXCLUDED.gpu_count,
    storage_class=EXCLUDED.storage_class,
    network_policy=EXCLUDED.network_policy,
    cloud_provider=EXCLUDED.cloud_provider,
    region=EXCLUDED.region,
    hpc_cluster_name=EXCLUDED.hpc_cluster_name,
    queue_or_partition=EXCLUDED.queue_or_partition,
    account_or_project=EXCLUDED.account_or_project,
    security_profile=EXCLUDED.security_profile,
    compliance_profile=EXCLUDED.compliance_profile,
    metadata=EXCLUDED.metadata,
    updated_at=now();

-- =============================================================================
-- V10+ explicit script contracts: dependencies, expected artifacts, execution
-- targets, CLI options, and contract checks.
-- =============================================================================

-- B001_01 is the first foundation script and intentionally has no upstream
-- script dependency. This row makes that design decision explicit for auditors.
INSERT INTO registry.script_dependencies (
    script_id, depends_on_module_id, dependency_type, required,
    version_constraint, purpose, metadata
)
SELECT
    'B001_01', 'B001', 'self-contained-foundation', false,
    '>=1.0.0',
    'Foundation preflight is the root script for the governed automation chain and has no upstream script dependency.',
    '{"upstream_scripts":[],"external_runtime_dependencies_recorded_in":"evidence.dependency_inventory","decision":"root-of-trust bootstrap"}'::jsonb
WHERE NOT EXISTS (
    SELECT 1 FROM registry.script_dependencies
    WHERE script_id='B001_01'
      AND dependency_type='self-contained-foundation'
      AND depends_on_module_id='B001'
);

INSERT INTO registry.script_expected_artifacts (
    script_id, artifact_type, artifact_name_pattern, required,
    retention_period, storage_backend, validation_rule, metadata
)
VALUES
('B001_01','audit_event','audit_events/{run_id}.jsonl',true,'7_years','PostgreSQL','{"must_have_run_id":true,"must_have_created_at":true,"append_only":true,"hash_chain":true}','{"purpose":"Regulated audit trail for every state change"}'),
('B001_01','step_log','steps/{run_id}.jsonl',true,'7_years','PostgreSQL','{"must_have_step_id":true,"must_have_status":true,"must_have_timestamps":true}','{"purpose":"Step-level execution traceability"}'),
('B001_01','dependency_inventory','dependencies/{run_id}.json',true,'7_years','PostgreSQL','{"must_include_runtime_tools":true,"must_include_versions_when_available":true}','{"purpose":"Runtime dependency and tool inventory"}'),
('B001_01','provenance','provenance/{run_id}.json',true,'7_years','PostgreSQL','{"must_include_git_commit":true,"must_include_container_digest":true,"must_include_actor":true}','{"purpose":"Reproducibility and lineage"}'),
('B001_01','validation_result','validation/{run_id}.json',true,'7_years','PostgreSQL','{"must_include_iq_oq_pq_status":true,"must_include_policy_gate_status":true}','{"purpose":"CSV and policy-gate evidence"}'),
('B001_01','artifact_manifest','manifests/{run_id}.json',true,'7_years','PostgreSQL','{"must_include_storage_uri":true,"must_include_sha256":true,"must_include_retention_period":true}','{"purpose":"Canonical produced-artifact manifest"}'),
('B001_01','execution_report_markdown','reports/{run_id}/execution_report.md',true,'7_years','PostgreSQL and rendered file','{"must_include_run_summary":true,"must_include_pass_fail":true,"must_include_artifact_table":true}','{"purpose":"Human-readable regulated execution report"}'),
('B001_01','sbom','sbom/{run_id}/b001.cdx.json',true,'7_years','S3 Object Lock','{"must_include_sha256":true,"format":"CycloneDX preferred"}','{"purpose":"Software bill of materials"}'),
('B001_01','trivy_report','security/{run_id}/trivy_report.json',true,'7_years','S3 Object Lock plus DB summary','{"must_include_scan_status":true,"must_include_critical_high_counts":true}','{"purpose":"Container/file vulnerability evidence"}'),
('B001_01','raw_log','logs/{run_id}/raw.log',true,'7_years','Loki/CloudWatch/S3','{"must_include_start_end_markers":true,"must_be_registered_by_uri":true}','{"purpose":"Raw execution log retention"}')
ON CONFLICT (script_id, artifact_type, artifact_name_pattern) DO NOTHING;

INSERT INTO registry.script_execution_targets (
    script_id, target, runtime, command_template, scheduler, container_runtime,
    environment_requirements, security_controls, description
)
VALUES
('B001_01','local','direct-bash','bash 01_foundation/b001_40_foundation_orchestrator.sh --target local --container-runtime docker --project-name biodiscoveryai',NULL,'docker','{"requires":["bash","docker","psql"],"database_env":"BDAI_DATABASE_URL"}','{"network_policy":"default-deny where possible","secrets":"environment or secret manager only","writes":"out/ and configured artifact path only"}','Run locally for development or controlled validation dry-runs.'),
('B001_01','hpc','direct-bash','bash 01_foundation/b001_40_foundation_orchestrator.sh --target hpc --container-runtime apptainer --project-name biodiscoveryai',NULL,'apptainer','{"requires":["bash","apptainer","psql optional","module system optional"],"database_env":"BDAI_DATABASE_URL or evidence API endpoint"}','{"container":"non-root","network":"disabled for foundation where feasible","filesystem":"read-only image plus explicit output bind"}','Run directly on an HPC login or compute node when scheduler wrapping is handled externally.'),
('B001_01','hpc','slurm','sbatch 01_foundation/b001_40_foundation_orchestrator.slurm','SLURM','apptainer','{"requires":["sbatch","apptainer","shared filesystem","approved partition/account"],"database_env":"BDAI_DATABASE_URL or evidence API endpoint"}','{"scheduler_audit":"SLURM job id captured","container":"immutable SIF","outputs":"run-scoped out/ directory"}','Run on HPC through SLURM using Apptainer.'),
('B001_01','aws','direct-bash','bash 01_foundation/b001_40_foundation_orchestrator.sh --target aws --container-runtime docker --project-name biodiscoveryai',NULL,'docker','{"requires":["awscli","docker","iam role or approved credentials","rds connectivity","s3 bucket"],"database_env":"BDAI_DATABASE_URL or Secrets Manager reference"}','{"iam":"least privilege","artifact_storage":"S3 Object Lock","logs":"CloudWatch/S3","secrets":"AWS Secrets Manager/SSM"}','Run on an AWS-managed instance or controlled build runner.'),
('B001_01','aws','aws-batch-nextflow','nextflow run main.nf -profile aws_batch --module B001 --script B001_01','AWS Batch','docker','{"requires":["nextflow","awscli","AWS Batch compute environment","ECR image","RDS/S3 connectivity"],"database_env":"evidence API preferred"}','{"iam":"task role least privilege","container":"digest-pinned ECR image","storage":"S3 Object Lock artifacts"}','Run through Nextflow on AWS Batch for production-style cloud orchestration.')
ON CONFLICT (script_id, target, runtime) DO NOTHING;

INSERT INTO registry.script_cli_options (
    script_id, option_name, value_name, required, default_value,
    allowed_values, description, example_value, applies_to_targets, metadata
)
VALUES
('B001_01','--target','TARGET',true,NULL,ARRAY['local','hpc','aws'],'Selects execution environment and activates target-specific checks, paths, and evidence fields.','hpc',ARRAY['local','hpc','aws'],'{"maps_to":"evidence.execution_runs.target"}'),
('B001_01','--container-runtime','RUNTIME',true,NULL,ARRAY['docker','apptainer','none'],'Selects runtime isolation mechanism. Use apptainer on HPC, docker locally/AWS, none only for approved bootstrap/debug cases.','apptainer',ARRAY['local','hpc','aws'],'{"security_impact":"high","must_record_in_provenance":true}'),
('B001_01','--project-name','NAME',false,'biodiscoveryai',ARRAY[]::TEXT[],'Logical project namespace used in output paths, labels, artifact prefixes, and reports.','biodiscoveryai',ARRAY['local','hpc','aws'],'{"naming_contract":"lowercase-hyphen-or-alphanumeric recommended"}'),
('B001_01','--run-id','RUN_ID',false,'auto-generated UTC run id',ARRAY[]::TEXT[],'Overrides generated run identifier. Required when rerunning a controlled validation scenario with pre-approved run naming.','B001-20260606T120000Z',ARRAY['local','hpc','aws'],'{"maps_to":"evidence.execution_runs.run_id","must_be_unique":true}'),
('B001_01','--out-dir','PATH',false,'./out/{run_id}',ARRAY[]::TEXT[],'Run-scoped output directory for generated reports, logs, manifests, and local cache artifacts.','/work/biodiscoveryai/out/B001-20260606T120000Z',ARRAY['local','hpc','aws'],'{"must_be_run_scoped":true}'),
('B001_01','--artifact-root','URI_OR_PATH',false,'target-specific default',ARRAY[]::TEXT[],'Root destination for registered artifacts. Use S3 Object Lock URI in AWS; use controlled shared filesystem or object-store gateway on HPC.','s3://bdai-evidence/B001/{run_id}/',ARRAY['hpc','aws'],'{"maps_to":"archive.artifacts.storage_uri"}'),
('B001_01','--evidence-endpoint','URL',false,NULL,ARRAY[]::TEXT[],'Evidence API endpoint used when scripts submit evidence through the gateway instead of direct database writes.','https://evidence-api.internal/v1',ARRAY['hpc','aws'],'{"preferred_for":"production"}'),
('B001_01','--database-url-env','ENV_NAME',false,'BDAI_DATABASE_URL',ARRAY[]::TEXT[],'Name of the environment variable containing the PostgreSQL connection URL for direct evidence writes.','BDAI_DATABASE_URL',ARRAY['local','hpc','aws'],'{"secret_handling":"never print value"}'),
('B001_01','--dry-run',NULL,false,'false',ARRAY['true','false'],'Validates configuration and planned actions without writing final evidence/artifacts except dry-run logs.','true',ARRAY['local','hpc','aws'],'{"regulated_use":"not a substitute for validation execution"}'),
('B001_01','--strict',NULL,false,'true',ARRAY['true','false'],'Fails execution on missing required governance, security, provenance, or artifact contract checks.','true',ARRAY['local','hpc','aws'],'{"recommended":"always true in controlled environments"}'),
('B001_01','--help',NULL,false,NULL,ARRAY[]::TEXT[],'Prints command-line usage and exits.','--help',ARRAY['local','hpc','aws'],'{}')
ON CONFLICT (script_id, option_name) DO NOTHING;

INSERT INTO registry.script_contract_checks (
    script_id, check_name, check_type, severity, required, rule, remediation
)
VALUES
('B001_01','module-lineage-present','lineage','Critical',true,'{"required_fields":["script_id","module_id","run_id"],"tables":["registry.scripts","evidence.execution_runs"]}','Register the script in registry.scripts and create every run with script_id and module_id.'),
('B001_01','expected-artifacts-registered','artifact-contract','Critical',true,'{"compare":"registry.script_expected_artifacts vs archive.artifacts","required_only":true}','Register every required artifact with storage_uri, sha256, retention_period, and immutable/legal-hold status where applicable.'),
('B001_01','runtime-dependencies-captured','dependency-contract','High',true,'{"runtime_table":"evidence.dependency_inventory","required":true}','Capture command/tool/runtime dependency inventory during execution.'),
('B001_01','hpc-aws-execution-documented','execution-contract','High',true,'{"required_targets":["hpc","aws"],"table":"registry.script_execution_targets"}','Add execution target rows with command templates, environment requirements, and security controls.'),
('B001_01','cli-options-documented','cli-contract','High',true,'{"minimum_options":["--target","--container-runtime","--project-name","--run-id","--out-dir"]}','Add CLI option rows with description, defaults, allowed values, and applicable targets.')
ON CONFLICT (script_id, check_name) DO NOTHING;
