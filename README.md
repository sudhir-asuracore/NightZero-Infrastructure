# NightZero Infrastructure 🌌
### Cloud Provisioning, Logging Sinks, and IAM Automation

[![Google Cloud Platform](https://img.shields.io/badge/GCP-Cloud%20Run%20%2B%20Logging-4285F4?style=for-the-badge&logo=googlecloud)](https://cloud.google.com)
[![Firestore](https://img.shields.io/badge/Storage-Cloud%20Firestore-FFA000?style=for-the-badge&logo=firebase)](https://cloud.google.com/firestore)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge)](LICENSE)

---

## 📌 Overview

This repository contains deployment automation, GCP service configurations, and scripts for provisioning the production NightZero ecosystem on Google Cloud Platform.

---

## 🏛️ GCP Infrastructure Blueprint

```mermaid
flowchart TD
    subgraph Compute["Google Cloud Run"]
        Agent["nightzero-agent\n(us-central1)"]
        Target["demo-payment-gateway\n(us-central1)"]
    end

    subgraph Telemetry["GCP Observability"]
        LoggingSink["Cloud Logging Alert Sink\n(severity >= ERROR)"]
    end

    subgraph Data["Persistence & IAM"]
        Firestore[("Cloud Firestore\n(Native Database)")]
        SecretManager["Secret Manager\n(GitHub Tokens & Keys)"]
        IAM["Service Account\n(roles/aiplatform.user)"]
    end

    Target -->|Structured JSON Exception| LoggingSink
    LoggingSink -->|HTTP Webhook| Agent
    Agent <--> Firestore
    Agent <--> IAM
    Agent <--> SecretManager
```

---

## 🛠️ Automated Setup Scripts

### 1. `deploy_gcloud.sh`
Automates deployment of the `nightzero-agent` service to Google Cloud Run with Vertex AI configuration:
```bash
./scripts/deploy_gcloud.sh
```

### 2. `setup_test_project_e2e.sh`
Sets up the end-to-end telemetry sink and Cloud Run deployment for `demo-payment-gateway`:
```bash
./scripts/setup_test_project_e2e.sh
```

---

## 📜 License
Licensed under the [Apache License 2.0](LICENSE).
