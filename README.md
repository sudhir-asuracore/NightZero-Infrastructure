# NightZero Infrastructure

Infrastructure deployment automation for the NightZero hackathon stack.

## Architecture

- Cloud Run hosts the public Agent API and signed GitHub webhook endpoint.
- Firestore stores durable incident artifacts.
- Secret Manager supplies Agent-only GitHub, webhook, Gemini, and clone credentials.
- Artifact Registry stores the Agent image.
- Firebase provides Authentication and Hosting for the Control Panel.

## Prerequisites

- A billed Google Cloud project and permission to enable APIs, manage IAM, and
  deploy Cloud Run.
- Firebase added to the same project in the Firebase Console; enable the desired
  sign-in provider before deploying the panel.
- `gcloud` CLI, Firebase CLI, Docker, and Node.js.

## Secrets Setup

Before deployment, ensure the following secrets are created in GCP Secret Manager:
- `nightzero-github-token`
- `nightzero-webhook-secret`
- `nightzero-gemini-api-key`
- `nightzero-git-clone-token` (a GitHub token used only by the Agent sandbox)

You can add them using:
```bash
gcloud secrets versions add nightzero-github-token --project "$PROJECT_ID" --data-file=-
```

## Deploy

From this repository, with `PROJECT_ID`, `FIREBASE_HOSTING_SITE_ID`, and `NIGHTZERO_REVIEWER_ALLOWLIST` exported, run:

```bash
./scripts/deploy_gcloud.sh
```

The script builds and pushes the Agent, deploys Cloud Run, builds the panel with the emitted Cloud Run URL, and deploys the Firebase Hosting target.

After deployment, update the repository's GitHub Issues webhook URL to `<agent_service_url>/api/v1/webhooks/github` and configure the webhook secret.

## Rollback and cleanup

To roll back the Agent, redeploy a previously pushed image tag. Roll back Hosting from the Firebase console release history. After the demo, disable the GitHub webhook, delete secret versions, and destroy the dedicated demo project resources using the GCP console.
