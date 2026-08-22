#!/usr/bin/env bash
# NightZero Zero-Friction Native GCP Deployment Script (Pure gcloud CLI)
# Usage: ./deploy_gcloud.sh

set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID to the Google Cloud project ID (e.g., export PROJECT_ID=my-gcp-project).}"
: "${FIREBASE_HOSTING_SITE_ID:=${PROJECT_ID}}"
: "${REGION:=us-central1}"
: "${NIGHTZERO_REVIEWER_ALLOWLIST:=nightzero-judges@asuracore.com,sidigrid@gmail.com}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
infra_dir="$(cd "${script_dir}/.." && pwd)"
workspace_dir="$(cd "${infra_dir}/.." && pwd)"
agent_dir="${workspace_dir}/NightZero-Agent"
panel_dir="${workspace_dir}/NightZero-ControlPanel"

image_tag="$(git -C "${agent_dir}" rev-parse --short HEAD 2>/dev/null || echo "latest")"
image_uri="${REGION}-docker.pkg.dev/${PROJECT_ID}/nightzero/agent:${image_tag}"

echo "============================================================"
echo "🚀 Deploying NightZero to GCP Project: ${PROJECT_ID}"
echo "============================================================"

# 1. Enable required GCP services
echo "📦 1/7 Enabling Google Cloud APIs..."
gcloud services enable \
  run.googleapis.com \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  firebase.googleapis.com \
  identitytoolkit.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Initialize Firestore Database (Native mode)
echo "🗄️ 2/7 Ensuring Firestore Native Database exists..."
if ! gcloud firestore databases describe --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud firestore databases create --location="${REGION}" --type=firestore-native --project="${PROJECT_ID}" || true
fi

# 3. Create Artifact Registry Docker Repository
echo "🐳 3/7 Setting up Artifact Registry repository..."
if ! gcloud artifacts repositories describe nightzero --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud artifacts repositories create nightzero \
    --repository-format=docker \
    --location="${REGION}" \
    --description="NightZero Agent Container Repository" \
    --project="${PROJECT_ID}"
fi

# 4. Build Agent Container Image via Cloud Build
echo "🔨 4/7 Building Agent Docker Image with Cloud Build..."
gcloud builds submit "${agent_dir}" \
  --project="${PROJECT_ID}" \
  --tag="${image_uri}"

# 5. Create Secret Manager Secret Containers (if not already existing)
echo "🔐 5/7 Setting up Secret Manager secret containers..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant Firestore access
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/datastore.user" >/dev/null

for secret_id in nightzero-gemini-api-key nightzero-github-token nightzero-git-clone-token nightzero-webhook-secret; do
  if ! gcloud secrets describe "${secret_id}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud secrets create "${secret_id}" --replication-policy="automatic" --project="${PROJECT_ID}"
    echo "  Created container: ${secret_id} (Add secret version via: gcloud secrets versions add ${secret_id} --data-file=...)"
  fi
  gcloud secrets add-iam-policy-binding "${secret_id}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT_ID}" >/dev/null
done

# 6. Deploy NightZero-Agent to Cloud Run
echo "☁️ 6/7 Deploying NightZero-Agent to Cloud Run..."
gcloud run deploy nightzero-agent \
  --image="${image_uri}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --platform="managed" \
  --allow-unauthenticated \
  --timeout="600s" \
  --concurrency=4 \
  --set-env-vars="NIGHTZERO_STORE_BACKEND=firestore,NIGHTZERO_AUTH_MODE=firebase,NIGHTZERO_REVIEWER_ALLOWLIST=${NIGHTZERO_REVIEWER_ALLOWLIST},NIGHTZERO_CORS_ORIGIN=https://${FIREBASE_HOSTING_SITE_ID}.web.app" \
  --set-secrets="GOOGLE_API_KEY=nightzero-gemini-api-key:latest,NIGHTZERO_GITHUB_TOKEN=nightzero-github-token:latest,NIGHTZERO_GIT_CLONE_TOKEN=nightzero-git-clone-token:latest,NIGHTZERO_WEBHOOK_SECRET=nightzero-webhook-secret:latest"

agent_url="$(gcloud run services describe nightzero-agent --region="${REGION}" --project="${PROJECT_ID}" --format='value(status.url)')"

# 7. Build and Deploy Control Panel to Firebase Hosting
echo "🎨 7/7 Building Control Panel & Deploying to Firebase Hosting..."
VITE_NIGHTZERO_API_URL="${agent_url}" \
VITE_FIREBASE_API_KEY="${VITE_FIREBASE_API_KEY:-demo}" \
VITE_FIREBASE_AUTH_DOMAIN="${VITE_FIREBASE_AUTH_DOMAIN:-${PROJECT_ID}.firebaseapp.com}" \
VITE_FIREBASE_PROJECT_ID="${PROJECT_ID}" \
VITE_FIREBASE_APP_ID="${VITE_FIREBASE_APP_ID:-demo}" \
npm --prefix "${panel_dir}" run build

if command -v firebase >/dev/null 2>&1; then
  firebase --project="${PROJECT_ID}" --config="${panel_dir}/firebase.json" deploy --only hosting
else
  echo "⚠️ 'firebase' CLI not found. To deploy Control Panel: npx firebase-tools --project=${PROJECT_ID} deploy --only hosting"
fi

echo ""
echo "============================================================"
echo "✅ NightZero Deployment Complete!"
echo "   Agent API URL:    ${agent_url}"
echo "   Control Panel:    https://${FIREBASE_HOSTING_SITE_ID}.web.app"
echo "   Cloud Logging Webhook: ${agent_url}/api/v1/webhooks/gcp-logging"
echo "============================================================"

# Set up the optional E2E infrastructure if requested (or just run it silently)
"${script_dir}/setup_test_project_e2e.sh"
