# OpenClaw Scripts

This repository contains operational scripts for OpenClaw setup and maintenance.

## Repository Structure

```
dgarwin-openclaw-scripts/
├── userdata.sh       # Main setup script (run by EC2 UserData)
└── sync-memory.sh    # Nightly backup script (syncs workspace to git)
```

## How It Works

This is part of a three-repository setup:

### 1. **dgarwin-openclaw-deployment**
   - Contains CloudFormation template
   - Defines infrastructure and IAM roles
   - **Access**: Admins only, NOT accessible to OpenClaw
   - **Security**: Prevents privilege escalation

### 2. **dgarwin-openclaw-scripts** (this repo)
   - Contains operational scripts
   - Cloned by CloudFormation during EC2 bootstrap
   - **Access**: Read-only by OpenClaw
   - **Purpose**: Setup and maintenance automation

### 3. **dgarwin-openclaw**
   - Contains workspace configuration and memory files
   - Holds **private/personal information** (schedule, preferences, memories)
   - Cloned by `userdata.sh` during setup
   - **Access**: Read-write by OpenClaw (for automatic memory sync)

## Deployment Flow

```
CloudFormation Template (deployment repo)
    ↓ provisions EC2 + IAM
    ↓ UserData clones scripts repo
    ↓
userdata.sh (this repo)
    ↓ clones config repo
    ↓ installs Node.js + OpenClaw
    ↓ configures workspace
    ↓
OpenClaw starts
    ↓ reads config from openclaw repo
    ↓ runs nightly sync-memory.sh
    ↓ commits memory changes back to openclaw repo
```

## Scripts

### userdata.sh
Main setup script executed during EC2 instance bootstrap. It:
- Fetches secrets from AWS SSM Parameter Store
- Configures GitHub authentication
- Clones the `dgarwin-openclaw` config repository
- Installs Node.js via NVM
- Installs and configures OpenClaw
- Sets up systemd service
- Copies workspace .md files

**Invoked by**: CloudFormation UserData
**Runs as**: root
**Environment variables required**:
- `OPENCLAW_REGION` - AWS region
- `OPENCLAW_STACK_NAME` - CloudFormation stack name
- `GH_PAT` - GitHub Personal Access Token

### sync-memory.sh
Nightly backup script that syncs workspace files to git. It:
- Copies workspace .md files to the config repo
- Copies cron jobs configuration
- Commits and pushes changes to GitHub

**Invoked by**: Cron job (runs at midnight EST)
**Runs as**: ubuntu user via systemEvent
**Syncs**:
- AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md, HEARTBEAT.md, MEMORY.md
- cron-jobs.json

## Security

- ✅ Scripts repo is read-only for OpenClaw
- ✅ No IAM role definitions (those stay in deployment repo)
- ✅ Scripts only operate on local filesystem and openclaw config repo
- ✅ Cannot modify deployment infrastructure

### Current Limitation: Self-Modifiable Config

⚠️ **OpenClaw currently has write access to its own `openclaw.json` configuration file** (in the `dgarwin-openclaw` repo). This means OpenClaw can modify its own permissions settings via the `gateway.config.patch` tool.

**Current mitigation**: We rely on:
- External IAM permissions (EC2 instance role limits what OpenClaw can do in AWS)
- GitHub repository permissions (deployment repo is not accessible)
- Agent design (built-in safety constraints)

**TODO**: Implement OS-level restrictions that cannot be circumvented:
- [ ] Use Linux capabilities/AppArmor/SELinux to restrict the OpenClaw process
- [ ] Mount openclaw.json as read-only in the CFN template
- [ ] Run OpenClaw in a container with strict resource limits
- [ ] Implement file-level permissions that prevent openclaw.json modification
- [ ] Use systemd service hardening (ProtectSystem=strict, ReadOnlyPaths, etc.)

This would provide defense-in-depth beyond relying on the agent's built-in safety.

## Local Testing

```bash
# Test userdata.sh (requires AWS credentials and secrets)
export OPENCLAW_REGION="us-east-2"
export OPENCLAW_STACK_NAME="test"
export GH_PAT="your-github-pat"
sudo bash userdata.sh

# Test sync-memory.sh
bash sync-memory.sh
```
