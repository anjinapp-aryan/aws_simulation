# Hands-On Score

Scoring basis: verified filesystem/execution evidence from `CURRENT-STATE.md`, not documentation completeness.

## Pre-phase application layer (connectivity-test / serverless-api / event-pipeline)

| Dimension | Score | Basis |
|---|---|---|
| Execution | 18/20 | 3 Spring apps, 3 Terraform roots, all actually run against Ministack |
| Observation | 18/20 | real S3/DynamoDB/SNS/SQS/Kinesis round-trips watched directly |
| Failure injection | 14/20 | one real scenario (malformed SNS message → DLQ), well executed; only one scenario, not several |
| Troubleshooting | 15/20 | genuine log-based diagnosis of the DLQ retry count and redrive |
| Recovery/verification | 16/20 | reprocessed and confirmed |
| **Total** | **81/100 — Good** | |

## Phase 1 — Terraform + Blueprint

| Dimension | Score | Basis |
|---|---|---|
| Execution | 3/20 | `fmt`/`validate`/`test` against someone else's repo; zero code authored |
| Observation | 4/20 | read test output, no infra observed |
| Failure injection | 0/20 | none |
| Troubleshooting | 3/20 | diagnosed one test failure's error message (correctly, later found version-specific) |
| Recovery/verification | 0/20 | nothing to recover |
| **Total** | **10/100 — Must redesign** | |

## Phase 2 — VPC & Networking

| Dimension | Score | Basis |
|---|---|---|
| Execution | 4/20 | test suite run on 2 TF versions + one scratch console experiment |
| Observation | 5/20 | real short-circuit error observed (small, language-level, not AWS) |
| Failure injection | 0/20 | 6 "experiments" explicitly labeled paper-only in their own README |
| Troubleshooting | 4/20 | correctly root-caused the TF version mismatch |
| Recovery/verification | 0/20 | nothing deployed, nothing to recover |
| **Total** | **13/100 — Must redesign** | |

## Phase 3 — IAM & Security Groups

| Dimension | Score | Basis |
|---|---|---|
| Execution | 11/20 | authored and ran a real `.tftest.hcl`; also ran the full 82-test suite |
| Observation | 10/20 | inspected real rendered IAM policy JSON, not mocked |
| Failure injection | 9/20 | genuine negative test — real injected violation, real detected failure message |
| Troubleshooting | 7/20 | found and fixed two real bugs in the test's own assertions; found the TF-version issue that invalidated Phase 1/2 conclusions |
| Recovery/verification | 8/20 | reverted the violation, reconfirmed clean pass |
| **Total** | **45/100 — Too theoretical** (clearly the strongest phaseN/ work, but still zero real infrastructure, zero container, zero network path ever observed) | |

## Interpretation
```
Pre-phase app layer:  81/100  Good
Phase 1:               10/100  Must redesign
Phase 2:                13/100  Must redesign
Phase 3:                45/100  Too theoretical
```
The project's own best work (the app layer) sits outside the phaseN/ structure entirely and was never referenced or built upon by it. The phaseN/ work, despite covering objectively harder and more valuable material (VPC, IAM, SG, the actual target architecture), scores far lower because it optimized for documentation completeness rather than executable experience — exactly the failure mode the user is now correcting for.
