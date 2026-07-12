# Wave 4 Storage Ownership Fix + Future CD Pipeline Design

**Date:** 2026-07-10
**Status:** Part 1 (fix) designed and agreed, not yet implemented. Part 2 (CD pipeline) is forward-looking design notes for after all four waves deploy cleanly end-to-end.

---

## Part 1: Fix the Wave 4 `scripts` container/blob ownership conflict

### Context

During today's from-scratch redeploy of all four waves (Linux dev machine, Waves 1–3 intentionally destroyed and reapplied), Wave 4 failed partway through `terraform apply`:

```
Error: A resource with the ID "https://sthlbdev001.blob.core.windows.net/scripts" already
exists - to be managed via Terraform this resource needs to be imported into the State.
```

**Root cause:** `environments/dev/wave4-cluster/main.tf` declares the `scripts` container and the `cluster-node-init.ps1` blob as Terraform `resource` blocks, meaning Wave 4 tries to *create* them fresh every apply. But the `scripts` container lives in Wave 0's storage account (`sthlbdev001`), which is never destroyed alongside Waves 1–4 — it survives every teardown. So this collision is not a one-off; it will happen on **every** from-scratch Wave 4 deploy until fixed.

**Blast radius when it fails:** the failed container resource blocks its dependents — `azurerm_role_assignment.cluster_scripts_reader` and both `azurerm_virtual_machine_extension` CSE resources (cn1, cn2) never run. Confirmed via `az vm extension list` after the failed apply: neither cluster node had any extension. Result: both cluster VMs come up on the network with correct NICs/disks, but are never domain-joined, never get Hyper-V/Failover Clustering installed, and never pull their DSC config.

### Why this design (vs. alternatives considered)

- **`terraform import` into Wave 4 state** — works, but re-breaks on the next from-scratch teardown/redeploy (the exact workflow this lab uses to validate fresh installs). Rejected.
- **Move ownership to Wave 0 (`bootstrap.ps1`), Wave 4 reads via `data` sources** — chosen. Wave 0 already creates the `scripts` container idempotently (skip-if-exists) and never gets destroyed, so it's the natural, durable owner. Confirmed both `data "azurerm_storage_container"` and `data "azurerm_storage_blob"` exist in the installed `hashicorp/azurerm` provider schema (checked via `terraform providers schema -json`), so this requires no new provider version.

### File Map

**Modify:**
- `scripts/bootstrap.ps1` — add one idempotent step: upload `vm-configs/cluster-node/init.ps1` to `scripts/cluster-node-init.ps1`
- `environments/dev/wave4-cluster/main.tf` — convert two `resource` blocks to `data` blocks; update one `scope` reference

**Not touched:** everything else in Waves 1–3, `modules/*`, DSC configs.

### Tasks

- [ ] **Step 1: Add blob upload step to `scripts/bootstrap.ps1`**

  Insert immediately after the existing "Storage Containers" step (after the `foreach ($containerName in @($storageContainerName, $scriptsContainerName))` loop, before the firewall-rules step — same rationale the script already documents: data-plane calls must happen before the firewall locks the account down to `$AllowedIpAddress`).

  ```powershell
  # -----------------------------------------------------------------------
  # Wave 4 cluster-node init script — uploaded here (not by Terraform) so
  # Wave 4 can reference it read-only via a data source. Always overwritten
  # so the container stays in sync with the repo's current init.ps1.
  # -----------------------------------------------------------------------
  Write-Step "Cluster-node init script -> $scriptsContainerName/cluster-node-init.ps1"
  try {
      [string]$clusterInitSource = Join-Path -Path $PSScriptRoot -ChildPath '..\vm-configs\cluster-node\init.ps1'
      if (-not (Test-Path -Path $clusterInitSource -PathType Leaf)) {
          throw "Source script not found: $clusterInitSource"
      }

      Set-AzStorageBlobContent `
          -Context     $storageContext `
          -Container   $scriptsContainerName `
          -Blob        'cluster-node-init.ps1' `
          -File        $clusterInitSource `
          -Force `
          -ErrorAction Stop | Out-Null

      Write-Done "Uploaded."
  }
  catch {
      throw "Failed to upload cluster-node init script: $($_.Exception.Message)"
  }
  ```

  Note: `$storageContext` is already in scope from the container-creation step above it (PowerShell `try` blocks don't create a new variable scope).

  Optionally: add a line to the `.DESCRIPTION` comment-based help and the completion summary (`Write-Host "Cluster-node script : uploaded to scripts container"`) for consistency with the existing style — not required for correctness.

- [ ] **Step 2: Convert `wave4-cluster/main.tf` resources to data sources**

  Replace:
  ```hcl
  resource "azurerm_storage_container" "scripts" {
    name                  = "scripts"
    storage_account_name  = "sthlbdev001"
    container_access_type = "private"
  }

  resource "azurerm_storage_blob" "cluster_init" {
    name                   = "cluster-node-init.ps1"
    storage_account_name   = "sthlbdev001"
    storage_container_name = azurerm_storage_container.scripts.name
    type                   = "Block"
    source                 = "${path.root}/../../../vm-configs/cluster-node/init.ps1"
  }
  ```

  With:
  ```hcl
  # Container and blob are created/uploaded by scripts/bootstrap.ps1 (Wave 0), not
  # Terraform — they live in Wave 0's storage account and must survive Wave 4
  # destroy/recreate cycles without Wave 4 trying to own their lifecycle.
  data "azurerm_storage_container" "scripts" {
    name                 = "scripts"
    storage_account_name = "sthlbdev001"
  }

  data "azurerm_storage_blob" "cluster_init" {
    name                   = "cluster-node-init.ps1"
    storage_account_name   = "sthlbdev001"
    storage_container_name = data.azurerm_storage_container.scripts.name
  }
  ```

- [ ] **Step 3: Update the role assignment scope**

  `azurerm_role_assignment.cluster_scripts_reader.scope` must change from `azurerm_storage_container.scripts.id` to `data.azurerm_storage_container.scripts.resource_manager_id` — the data source exposes the ARM resource ID under a different attribute name than the resource did.

  ```hcl
  resource "azurerm_role_assignment" "cluster_scripts_reader" {
    scope                = data.azurerm_storage_container.scripts.resource_manager_id
    role_definition_name = "Storage Blob Data Reader"
    principal_id         = azurerm_user_assigned_identity.cluster_scripts.principal_id
  }
  ```

  No change needed to `fileUris = [data.azurerm_storage_blob.cluster_init.url]` in either CSE resource — `.url` is the same attribute name on both the old resource and the new data source.

- [ ] **Step 4: Re-run bootstrap.ps1**

  Interactive (Azure login + confirmation prompt) — run manually:
  ```powershell
  .\scripts\bootstrap.ps1 -SubscriptionId 'e61ca020-85e9-4d96-8947-b331a6b295fd' -AllowedIpAddress '<your current public IP>'
  ```
  Everything in the script is idempotent (skip-if-exists for RG/SA/KV/containers, overwrite for the new blob step), so this is safe to run against the existing Wave 0 resources.

- [ ] **Step 5: Re-plan and apply Wave 4**

  From `environments/dev/wave4-cluster/`:
  ```
  terraform init -upgrade    # picks up no new resource types, but safe
  terraform plan -out=./wave4-cluster.plan
  terraform apply "./wave4-cluster.plan"
  ```
  No `terraform state rm` needed — the container/blob resources never successfully entered Wave 4's state (the apply failed before they were recorded), so there's nothing to migrate.

### Verification

- `terraform plan` shows the two `data` sources resolving successfully (no "already exists" error) and a clean plan with all 26 resources (or fewer, since the container/blob are no longer Wave-4-managed resources — expect ~24: 26 minus the container and blob).
- `terraform apply` completes with 0 errors.
- `az vm extension list --vm-name vm-cn-dev-001 -g rg-hlb-dev-cluster-001` and same for `vm-cn-dev-002` each show the `CustomScriptExtension` in `Succeeded` state.
- `C:\configure-node-validation.log` on both nodes shows all checks `[PASS]` (retrieve via `az vm run-command invoke` or RDP via Bastion).
- `.\dsc-configs\cluster-node\publish.ps1 -ConfigurationId ee96e6d2-28b4-4ef3-b8ec-551ce58a1a18` can then be run from the DSC pull server to complete cluster node configuration.
- Re-running `bootstrap.ps1` a second time in a row produces no changes (fully idempotent) — good regression check to run once after Step 4.

---

## Part 2: CD Pipeline Design (next step, after Wave 4 deploys cleanly end-to-end)

### Goal

Once the Part 1 fix is verified and a from-scratch four-wave deploy succeeds without manual intervention, encode today's manual orchestration into a CI/CD pipeline (GitHub Actions or Azure DevOps — not yet decided) so `git push` (or a manual trigger) can redeploy the whole lab unattended.

### The exact logic flow exercised manually today — this is the spec for the pipeline

This is the sequence that was actually run this session, wave by wave, and should map directly onto pipeline stages/jobs:

1. **Pre-flight: tfvars completeness check.** For each wave, diff the no-default variables in `variables.tf` against the keys present in `terraform.tfvars` (done today with a small `awk` script). In a pipeline, `terraform.tfvars` won't exist as a file at all — see "Secrets injection" below; this step becomes "are all required pipeline variables/secrets set."

2. **Per wave, strictly sequential, each gated on the previous wave's success:**
   - `terraform init -input=false`
   - `terraform plan -input=false -out=<wave>.plan` — inspect the plan summary (add/change/destroy counts) before proceeding
   - `terraform apply -input=false "<wave>.plan"` — apply the *exact* saved plan, never a bare `apply` in CI, so what's reviewed is what runs
   - **Hard stop on any failure** — do not attempt the next wave. This matters especially for Waves 2–4, which read the previous wave's outputs via `terraform_remote_state`; if Wave N's apply fails or is incomplete, Wave N+1's plan will itself fail (as seen today) or, worse, silently apply against stale/partial outputs.

3. **Wave-specific health checks beyond "apply succeeded."** `terraform apply` returning 0 only proves the ARM deployment succeeded — for waves with two-phase CSE + scheduled-task init (Wave 3 DC/CA, Wave 4 cluster nodes), the *actual* configuration work finishes asynchronously after apply returns. Today's session used `az vm run-command invoke` to verify real state post-apply:
   - Wave 2: `Invoke-WebRequest https://localhost:8080/PSDSCPullServer.svc` → expect `200`
   - Wave 3: `Get-ADDomain` (NetBIOS, DomainMode) + `Get-Service ADWS,DNS,NTDS` on the DC; `Get-Service CertSvc` + domain membership on the CA
   - Wave 4: `az vm extension list` to confirm CSE `Succeeded`, then read `C:\configure-node-validation.log` for the 10 PASS/FAIL checks
   A pipeline should encode each of these as an explicit post-apply verification step per wave, not just trust the Terraform exit code.

4. **Quota pre-check before Wave 4** (or before any wave adding compute). Today's session validated vCPU quota manually with `az vm list-usage --location southcentralus` and cross-referenced SKU→family mappings via `az vm list-skus`. A pipeline step should do this automatically and fail fast with a clear message rather than let Wave 4 partially apply and hit a quota error mid-deployment.

5. **Post-deploy subscription inventory as a final validation gate** — after all waves apply, enumerate actual Azure state and diff against expectations, rather than trusting Terraform state alone:
   - `az group list` — all expected RGs present
   - `az vm list -d` — all VMs running, correct SKU, correct private IPs
   - `az disk list -g <cluster-rg>` — shared disks present with correct `maxShares`
   - `az storage container list` — expected containers present
   - `az role assignment list --scope <container>` — managed identity has the expected role (this would have caught today's failure immediately)

6. **Error capture and reporting.** When a wave fails partway (like Wave 4 today), the pipeline should surface: which specific resource failed and why (parse the `Error:` block), `terraform state list` diffed against the full plan to show exactly what did/didn't get created, and stop the run — don't attempt cleanup/rollback automatically, since partial infrastructure (e.g. VMs without their CSE-driven config) may still be intentionally worth keeping for debugging.

### Proposed pipeline shape (draft, to refine when this is picked up)

- One job/stage per wave (`wave1-net`, `wave2-dsc`, `wave3-dc`, `wave4-cluster`), each with explicit `needs:`/`dependsOn` on the previous wave's job — mirrors the `terraform_remote_state` dependency chain already in the code.
- Each job: `terraform init` → `terraform plan` (upload plan as a build artifact for review) → optional manual-approval gate → `terraform apply` → wave-specific health-check script (from item 3 above).
- Final job after Wave 4: subscription inventory validation (item 5) + summary report.
- **Secrets injection:** replace local `terraform.tfvars` files with pipeline-native secret variables (GitHub Actions secrets / Azure DevOps variable groups, ideally backed by the Wave 0 Key Vault via OIDC federation) — `subscription_id`, `admin_cidr`, `cluster_node_config_id` should never be committed, matching the existing `.gitignore` treatment of `*.tfvars`.
- Authentication: OIDC federated credential (GitHub Actions `azure/login@v2` with `id-token: write`, or Azure DevOps Workload Identity Federation) instead of a long-lived service principal secret.
- Trigger: manual (`workflow_dispatch`) initially, given this is a lab that gets torn down between sessions to control cost — not a push-triggered pipeline.

### Open questions for when this is picked up

- Should teardown (`terraform destroy`, reverse wave order) also be pipeline-driven, given this session's pattern of deliberately tearing down between validation runs?
- Where do DSC `publish.ps1` steps (which run *from* the DSC pull server, not from the pipeline runner) fit into a hosted pipeline — likely need `az vm run-command` to invoke them remotely rather than needing network access to the pull server from the runner.
- Whether to gate each wave behind a manual approval (safer, matches how this session proceeded — plan reviewed before every apply) or run unattended end-to-end once Part 1's fix is proven stable across a few from-scratch runs.
