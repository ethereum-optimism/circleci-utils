---
name: release-and-rollout
description: How a change in this repo actually reaches CI - the two tag series, cutting a v* source tag, publishing an orb version, and bumping consumer pins. Read this before or after merging any fix that needs to run in production CI.
---

# Release and rollout

Merging a PR here deploys nothing. There are two independent release channels, and a
change only reaches CI once both have been advanced *and* the consumer's orb pin bumped.

## Two tag series - don't confuse them

| Tag         | Releases                                                              | Example      |
| ----------- | --------------------------------------------------------------------- | ------------ |
| `vX.Y.Z`    | The source tree (`github_utility/`, scripts) that jobs clone at runtime | `v0.6.1`     |
| `orb/X.Y.Z` | Bookkeeping mirror of a published CircleCI orb version                 | `orb/1.0.30` |

The two version numbers are unrelated. Orb versions live in CircleCI, not in git -
`orb/*` tags are only created after the fact by `orb/publish-prod-repository-tag.sh`
and are not what CircleCI serves.

## Why merging deploys nothing

`orb/src/commands/setup-circleci-utils-and-github-token.yml` clones this repo at a tag:

```yaml
git clone --branch << parameters.circleci-utils-tag >> --depth 1 \
  https://github.com/ethereum-optimism/circleci-utils.git /tmp/circleci-utils
```

`circleci-utils-tag` has a `default` in that file, and that default is frozen into every
*published* orb version. A consumer pinned to `circleci-utils@1.0.30` runs whatever tag
1.0.30 was published with, no matter what `main` says. The default sat at `v0.5.0` up to
and including orb 1.0.30, so production ran that code for a long time after fixes merged.

No orb command forwards `circleci-utils-tag` to the setup command, so consumers cannot
pick up new source code by passing a parameter to the command they actually call.

## The full chain

1. Merge the PR to `main`.
2. Cut a source tag at the merge commit: `git tag vX.Y.Z <merge-sha> && git push origin vX.Y.Z`.
3. Bump `circleci-utils-tag`'s `default` to `vX.Y.Z` in
   `orb/src/commands/setup-circleci-utils-and-github-token.yml` and merge that.
4. Publish a new orb version - `orb/publish-dev.sh`, test, then `orb/publish-prod.sh` -
   and push the `orb/X.Y.Z` tag. See [Development & Release Process](../../../README.md#development--release-process).
5. Bump every consumer's orb pin. For the monorepo that's
   `ethereum-optimism/circleci-utils@<version>` in `.circleci/continue/main.yml`.

Nothing is live until step 5.

Steps 2 and 3 apply only to changes in the cloned source tree. A change to orb YAML alone
needs steps 1, 4 and 5.

## Who can publish

Publishing a production orb version requires GitHub org **Owner**; org Members can only
publish `dev:` versions. If you're not an owner, ask in **#eng-oncall** - see
[Permissions & Access](../../../README.md#permissions--access).

## Checking what's actually published

The orb is private, so `https://circleci.com/api/v2/orb/ethereum-optimism/circleci-utils`
returns 404. Use the CircleCI GraphQL API instead; reads need no token.

List published versions:

```bash
curl -s https://circleci.com/graphql-unstable \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orb(name: \"ethereum-optimism/circleci-utils\") { isPrivate versions { version createdAt } } }"}'
```

Read a published version's full source - the only reliable way to see which
`circleci-utils-tag` a version really shipped with:

```bash
curl -s https://circleci.com/graphql-unstable \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orbVersion(orbVersionRef: \"ethereum-optimism/circleci-utils@1.0.30\") { source } }"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["orbVersion"]["source"])' \
  | grep -A2 circleci-utils-tag
```

## Escape hatch for an urgent rollout

A consumer can force a source tag without waiting on an orb publish, by running the setup
command itself first with an explicit tag:

```yaml
- utils/github-stale:
    pre-steps:
      - utils/setup-circleci-utils-and-github-token:
          circleci-utils-tag: v0.6.1
```

This works because the setup command clones only if `/tmp/circleci-utils` doesn't exist,
so the later internal call is a no-op.

Use it as a temporary bridge only. Publishing an orb version is the right fix - an override
has to be repeated in every consumer and leaves the stale default in place everywhere else.

## Verify after rollout

Check a real job on the consumer, not just the config diff. The `Setup circleci-utils` step
logs the tag it clones; if it's still the old one, the orb version you pinned still carries
the old default - go back to step 4.

## Checklist

- [ ] PR merged to `main`
- [ ] `vX.Y.Z` tag cut at the merge commit and pushed
- [ ] `circleci-utils-tag` default bumped to `vX.Y.Z` and merged
- [ ] New orb version published and `orb/X.Y.Z` tag pushed
- [ ] Published orb source confirmed to carry the new default (GraphQL `orbVersion`)
- [ ] Consumer pins bumped (monorepo: `.circleci/continue/main.yml`)
- [ ] Consumer job log shows the new tag being cloned
