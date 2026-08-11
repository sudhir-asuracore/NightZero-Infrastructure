#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID to the Google Cloud project ID}"

agent_url="$(gcloud run services describe nightzero-agent --region="us-central1" --project="${PROJECT_ID}" --format='value(status.url)')"
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")

echo "🚀 Setting up TestProject E2E Infrastructure (PubSub, Log Sink, GitHub Actions IAM)..."

gcloud services enable iamcredentials.googleapis.com pubsub.googleapis.com logging.googleapis.com --project="${PROJECT_ID}"

echo "📡 Configuring Pub/Sub and Cloud Logging Webhook..."
if ! gcloud pubsub topics describe nightzero-alerts --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud pubsub topics create nightzero-alerts --project="${PROJECT_ID}"
fi
if ! gcloud pubsub subscriptions describe nightzero-webhook-sub --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud pubsub subscriptions create nightzero-webhook-sub \
    --topic=nightzero-alerts \
    --push-endpoint="${agent_url}/api/v1/webhooks/gcp-logging" \
    --project="${PROJECT_ID}"
fi
if ! gcloud logging sinks describe nightzero-error-sink --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud logging sinks create nightzero-error-sink \
    pubsub.googleapis.com/projects/${PROJECT_ID}/topics/nightzero-alerts \
    --log-filter='resource.type="cloud_run_revision" AND severity>=ERROR' \
    --project="${PROJECT_ID}"
  
  SINK_SA=$(gcloud logging sinks describe nightzero-error-sink --project="${PROJECT_ID}" --format='value(writerIdentity)')
  gcloud pubsub topics add-iam-policy-binding nightzero-alerts \
    --member="${SINK_SA}" \
    --role="roles/pubsub.publisher" \
    --project="${PROJECT_ID}" >/dev/null
fi

echo "🔗 Setting up GitHub Workload Identity Pool..."
gcloud iam workload-identity-pools create github-pool --project="${PROJECT_ID}" --location="global" --display-name="GitHub Actions Pool" || true
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project="${PROJECT_ID}" --location="global" --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == 'sudhir-asuracore'" \
  --issuer-uri="https://token.actions.githubusercontent.com" || true

if ! gcloud iam service-accounts describe github-actions@${PROJECT_ID}.iam.gserviceaccount.com --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create github-actions --project="${PROJECT_ID}"
fi
for role in roles/run.admin roles/iam.serviceAccountUser roles/artifactregistry.writer; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="${role}" >/dev/null
done
gcloud iam service-accounts add-iam-policy-binding "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/sudhir-asuracore/NightZero-TestProject" >/dev/null

echo "✅ TestProject E2E Setup Complete"
