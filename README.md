# circleci-utils

Utility to use with CircleCI - A collection of reusable CircleCI orb components.

## Overview

This repository contains CircleCI orb utilities that can be published and used across different projects. The orb is published under `ethereum-optimism/circleci-utils`.

## Prerequisites

- CircleCI CLI installed (`brew install circleci` or see [CircleCI CLI documentation](https://circleci.com/docs/local-cli/))
- CircleCI personal API token (get one from [CircleCI User Settings](https://app.circleci.com/settings/user/tokens))
- Git access to this repository
- Appropriate permissions (see [Permissions & Access](#permissions--access) below)

## Permissions & Access

### Who Can Publish Orbs?

**To publish a production orb version, you must be a GitHub organization owner.**

If you need to publish an orb but don't have owner permissions, ask in **#eng-oncall** on Slack. Either **CloudSecurity** or someone from **Infra** will be able to help you publish it.

### Why These Restrictions?

CircleCI orb publishing permissions are tied to GitHub organization roles. Here's how it works:

#### 1. Production (SemVer) Orbs

To publish production versions (e.g., `1.2.3`):
- **Required role:** GitHub organization **Owner/Admin**
- **What you can do:**
  - `circleci namespace create`
  - `circleci orb create`
  - `circleci orb publish` (production version)

#### 2. Development Orbs

To publish development versions (e.g., `dev:feat-my-branch`):
- **Required role:** GitHub organization **Member** (any member)
- **What you can do:**
  - `circleci orb publish` (development version)

#### 3. CircleCI Org Role Matrix

| Role | Create/Update Orb | Publish Dev Orb | Publish Production Orb |
|------|-------------------|-----------------|------------------------|
| **Admin** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Contributor** | ❌ No | ✅ Yes | ❌ No |
| **Viewer** | ❌ No | ❌ No | ❌ No |

### For Non-Owners: How to Publish Production Orbs

If you're not an organization owner but need to publish production orbs:

**Ask in #eng-oncall on Slack** and request help from CloudSecurity or Infra team members who have owner permissions.

#### Alternative Approach (Not Used)
While CircleCI technically supports allowing non-owners to publish via a shared context with an owner's API token, **we have decided NOT to use this approach** because:
- Personal API tokens grant **full read and write permissions** and cannot be scoped to only orb publishing
- The risk of a leaked token with this much power is too high
- Orb publishing happens infrequently enough that the manual approval process via #eng-oncall is more secure and practical

**There is only one supported option:** ask in **#eng-oncall**.

### GitHub OIDC Integration

Even with CircleCI connected via GitHub OIDC/App integration, the permission requirements remain the same:
- **Production orb publishing:** GitHub organization **Owner** role required
- **Development orb publishing:** GitHub organization **Member** role sufficient

### Common Permission Errors

If you see errors like:
```
User does not have access to publish SemVer orbs in this namespace
```

This usually means:
- You are not a GitHub org owner/admin for the `ethereum-optimism` namespace, or
- Your API token is invalid/expired

**Solution:** Ask for help in **#eng-oncall** on Slack.

## Development & Release Process

### 1. Development - Publishing Dev Versions

**Anyone can publish a dev version** using their personal CircleCI token. Dev versions are used for testing changes before they go to production.

#### Steps to Publish Dev Version:

1. Make your changes in a feature branch (e.g., `feat-my-branch`)
2. Navigate to the `orb` directory:
   ```bash
   cd orb
   ```
3. Run the publish-dev script:
   ```bash
   ./publish-dev.sh
   ```

The script will:
- Validate the orb configuration
- Pack the orb from the `src/` directory
- Publish to CircleCI as `ethereum-optimism/circleci-utils@dev:feat-my-branch`

**Note:** The branch name is automatically sanitized (slashes are converted to hyphens) and used as the dev version label.

### 2. Testing Dev Versions

After publishing a dev version, **you must test it before promoting to production**.

To test your dev version, use it in another project's `.circleci/config.yml`:

```yaml
version: 2.1

orbs:
  utils: ethereum-optimism/circleci-utils@dev:feat-my-branch

workflows:
  # Your workflow using the dev orb
```

**Important:** Replace `feat-my-branch` with your actual branch name (with slashes converted to hyphens).

#### Listing Available Dev Versions:

```bash
circleci orb list ethereum-optimism/circleci-utils
```

### 3. Promoting to Production

Once your dev version has been tested and approved, you can promote it to production.

**⚠️ Important:** Production orb publishing requires GitHub organization owner permissions. If you don't have owner access, ask in **#eng-oncall** on Slack for help from CloudSecurity or Infra team.

#### Steps to Promote to Production:

1. Ensure you're ready to release (changes are tested and approved)
2. Navigate to the `orb` directory:
   ```bash
   cd orb
   ```
3. Run the publish-prod script:
   ```bash
   ./publish-prod.sh
   ```

The script will:
- Validate the orb configuration
- Prompt you to enter the **branch name** (dev version label) to promote
  - Example: If you published `dev:feat-my-branch`, enter `feat-my-branch`
- Ask for confirmation before promoting
- Promote the dev version to production with a **patch** version increment
- Optionally tag the repository (see next section)

**Important:** You need to specify the exact branch name that was used for the dev version you want to promote.

### 4. Repository Tagging

To keep the repository tags in sync with the published orb versions, you can tag the repository after promoting to production.

#### Option A: Automatic Tagging (Recommended)

When running `./publish-prod.sh`, you'll be prompted:
```
Do you want to tag the repository with the orb version? (Y/n)
```

Press `Y` or `Enter` to automatically tag the repository.

#### Option B: Manual Tagging

If you skipped tagging during promotion or need to tag separately, run:

```bash
./publish-prod-repository-tag.sh
```

**Requirements for Tagging:**
- Must be run from the `main` branch
- The script will:
  - Get the latest orb version from CircleCI
  - Create a git tag: `orb/<version>` (e.g., `orb/1.2.3`)
  - Push the tag to the remote repository

This keeps the repository tags synchronized with the orb versions.

## Script Reference

### `publish-dev.sh`
- **Purpose:** Publish dev versions for testing
- **Who can run:** Any GitHub organization member with a CircleCI token
- **Branch:** Any branch
- **Output:** `ethereum-optimism/circleci-utils@dev:<branch-name>`
- **Permissions needed:** GitHub org Member role

### `publish-prod.sh`
- **Purpose:** Promote a tested dev version to production
- **Who can run:** GitHub organization owners/admins only (or ask #eng-oncall in Slack)
- **Branch:** Any branch (typically `main`)
- **Actions:** Promotes dev to production (patch version) and optionally tags repository
- **Permissions needed:** GitHub org Owner/Admin role

### `publish-prod-repository-tag.sh`
- **Purpose:** Tag the repository with the latest orb version
- **Who can run:** Team members with git push permissions
- **Branch:** Must be run from `main` branch only
- **Output:** Creates and pushes git tag `orb/<version>`
- **Permissions needed:** Git push access to the repository

## Workflow Summary

```
1. Create feature branch (feat-my-branch)
   ↓
2. Make changes to orb
   ↓
3. Run ./publish-dev.sh (any org member can do this)
   → Publishes ethereum-optimism/circleci-utils@dev:feat-my-branch
   ↓
4. Test dev version in another project
   orbs:
     utils: ethereum-optimism/circleci-utils@dev:feat-my-branch
   ↓
5. Merge to main (after approval)
   ↓
6. Run ./publish-prod.sh from main (requires org owner or ask #eng-oncall)
   → Enter branch name: feat-my-branch
   → Confirm promotion
   → Optionally tag repository
   ↓
7. New production version released!
   → Repository tagged with orb/<version>
```

## Best Practices

1. **Always test dev versions** before promoting to production
2. **Use descriptive branch names** - they become part of the dev version identifier
3. **Promote from main** - Ensure your changes are merged to main before promoting
4. **Tag the repository** - Keep repository tags in sync with orb versions for traceability
5. **Document breaking changes** - If your changes break existing functionality, communicate this to users
6. **Plan ahead for production releases** - If you're not a GitHub org owner, coordinate with #eng-oncall in Slack before you need to publish
7. **Test thoroughly** - Since only owners can publish production, make sure your dev version is thoroughly tested to avoid multiple release cycles

## Troubleshooting

### "User does not have access to publish SemVer orbs in this namespace"
- **Cause:** You're not a GitHub organization owner/admin, or your API token is invalid
- **Solution:** Ask for help in **#eng-oncall** on Slack (CloudSecurity or Infra team can publish for you)
- **Alternative:** Verify your CircleCI token is valid and not expired

### "orb.yml is not valid"
- Check the syntax in your orb source files
- Ensure all required fields are present
- Review CircleCI orb documentation for schema requirements

### "Could not retrieve orb version" (during tagging)
- Ensure the orb was successfully published
- Check your CircleCI token has correct permissions
- Verify the orb name is correct: `ethereum-optimism/circleci-utils`

### "Repository tagging can only be done from the main branch"
- Switch to the main branch: `git checkout main`
- Pull latest changes: `git pull origin main`
- Run the tagging script again

### Dev version published but can't find it
- List available versions: `circleci orb list ethereum-optimism/circleci-utils`
- Check that the branch name was sanitized correctly (slashes become hyphens)
- Verify you're using the correct namespace: `ethereum-optimism/circleci-utils`

## Additional Resources

- [CircleCI Orbs Documentation](https://circleci.com/docs/orb-intro/)
- [CircleCI CLI Documentation](https://circleci.com/docs/local-cli/)
- [Orb Publishing Guide](https://circleci.com/docs/creating-orbs/)
- [Orb Authoring Process](https://circleci.com/docs/orb-author/)
- [Organization Roles and Permissions](https://circleci.com/docs/roles-and-permissions/)
- [Managing API Tokens](https://circleci.com/docs/managing-api-tokens/)
- [Orb Publishing Permissions](https://circleci.com/docs/orb-author-validate-publish/#orb-publishing-permissions)

## Quick Reference

**Need to publish a production orb?**
→ Ask in **#eng-oncall** on Slack (CloudSecurity or Infra team)

**Want to test changes?**
→ Run `./publish-dev.sh` (any org member can do this)

**Check available versions:**
```bash
circleci orb list ethereum-optimism/circleci-utils
```

**Use dev version in your project:**
```yaml
orbs:
  utils: ethereum-optimism/circleci-utils@dev:your-branch-name
```
