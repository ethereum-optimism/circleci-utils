#!/bin/bash
# Test harness for github-commit-and-push-changes-single-file.yml
# Extracts the real script from the orb YAML, substitutes parameters as
# CircleCI would, and runs it against local sandbox repos.
# Test shims (the ONLY deviations from production):
#   1. push URL https://x-access-token:...github.com/... -> "origin"
#   2. SECRET_ACCESS_TOKEN_FILE_PATH -> fake token file
#   3. GIT_CONFIG_GLOBAL -> sandbox file (script does `git config --global`)
set -uo pipefail

ORB_YML="$(cd "$(dirname "$0")" && pwd)/../src/commands/github-commit-and-push-changes-single-file.yml"
ROOT=$(mktemp -d /tmp/orb-l1.XXXXXX)
PASS=0; FAIL=0

# --- extract the run script from the YAML (block after "command: |", 8-space indent)
extract_script() {
  sed -n '/^      command: |$/,$p' "$ORB_YML" | tail -n +2 | sed 's/^        //' > "$ROOT/raw.sh"
  # substitute orb parameters as CircleCI would
  sed -e 's/<< parameters.condition >>/always/g' \
      -e 's/<< parameters.branch >>/updated-addresses/g' \
      -e 's/<< parameters.file >>/list.json/g' \
      -e 's/<< parameters.commit-message >>/Updated List with new addresses/g' \
      -e 's/<< parameters.commit-username >>/tester/g' \
      -e 's/<< parameters.commit-email >>/tester@example.com/g' \
      -e 's/<< parameters.skip-ci >>/false/g' \
      "$ROOT/raw.sh" > "$ROOT/subst.sh"
  # test shim: push to local origin instead of github over https
  sed 's|"https://x-access-token:${token}@github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}.git"|origin|' \
      "$ROOT/subst.sh" > "$ROOT/script.sh"
  echo fake-token > "$ROOT/token"
}

# --- sandbox helpers
new_sandbox() {  # $1 = name
  SB="$ROOT/$1"; mkdir -p "$SB"
  git init -q --bare "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null
  export GIT_CONFIG_GLOBAL="$SB/gitconfig"
  git -C "$SB/work" config user.email seed@t && git -C "$SB/work" config user.name seed
  printf '[\n  "0xaaa",\n  "0xbbb"\n]\n' > "$SB/work/list.json"
  git -C "$SB/work" add . && git -C "$SB/work" commit -qm "init" && git -C "$SB/work" push -q origin main
}

seed_branch() {  # $1 = content-file source
  git -C "$SB/work" checkout -qb updated-addresses
  cp "$1" "$SB/work/list.json"
  git -C "$SB/work" commit -qam "seed branch" && git -C "$SB/work" push -q origin updated-addresses
  git -C "$SB/work" checkout -q main
}

run_script() {  # runs the extracted orb script inside work/, generated content already in tree
  ( cd "$SB/work" && \
    SECRET_ACCESS_TOKEN_FILE_PATH="$ROOT/token" \
    CIRCLE_PROJECT_USERNAME=x CIRCLE_PROJECT_REPONAME=y CIRCLE_USERNAME=tester \
    GIT_CONFIG_GLOBAL="$SB/gitconfig" \
    bash -eo pipefail "$ROOT/script.sh" ) > "$SB/out.log" 2>&1
  echo $?
}

check() {  # $1 = description, $2 = 0/1 result (0 = ok)
  if [ "$2" -eq 0 ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi
}

branch_file() { git -C "$SB/work" fetch -q origin && git -C "$SB/work" show origin/updated-addresses:list.json > "$SB/branch-file.json"; }

extract_script
echo "== extracted script: $(wc -l < "$ROOT/script.sh") lines =="

# ---------- Scenario A: incident replay (diverged branch WITH conflict markers)
echo; echo "=== A. diverged branch seeded with conflict-marker garbage (incident replay)"
new_sandbox A
cat > "$ROOT/corrupted.json" <<'EOF'
[
  "0xaaa",
<<<<<<< Updated upstream
<<<<<<< Updated upstream
  "0xbbb",
=======
  "0xccc",
>>>>>>> Stashed changes
=======
  "0xddd",
>>>>>>> Stashed changes
]
EOF
seed_branch "$ROOT/corrupted.json"
printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xnew1",\n  "0xnew2"\n]\n' > "$SB/work/list.json"   # freshly "generated"
rc=$(run_script)
check "script exits 0" "$rc"
branch_file; cp "$SB/branch-file.json" "$SB/final.json"
cmp -s "$SB/final.json" <(printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xnew1",\n  "0xnew2"\n]\n'); check "branch file == generated content exactly" $?
! grep -q '<<<<<<<\|>>>>>>>' "$SB/final.json"; check "no conflict markers" $?
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SB/final.json" 2>/dev/null; check "valid JSON" $?
git -C "$SB/work" log origin/updated-addresses --format=%s > "$SB/log.txt"; grep -q "seed branch" "$SB/log.txt"; check "branch history preserved (no force-push)" $?

# ---------- Scenario B: identical content -> no-op
echo; echo "=== B. branch already has identical content (no-op)"
new_sandbox B
printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xsame"\n]\n' > "$ROOT/same.json"
seed_branch "$ROOT/same.json"
cp "$ROOT/same.json" "$SB/work/list.json"
rc=$(run_script)
check "script exits 0" "$rc"
grep -q "No changes to commit" "$SB/out.log"; check "reports 'No changes to commit'" $?
[ "$(git -C "$SB/work" log origin/updated-addresses --oneline | wc -l | tr -d ' ')" = 2 ]; check "no new commit created" $?

# ---------- Scenario C: target branch does not exist remotely
echo; echo "=== C. target branch does not exist remotely"
new_sandbox C
printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xfresh"\n]\n' > "$SB/work/list.json"
rc=$(run_script)
check "script exits 0" "$rc"
branch_file; grep -q "0xfresh" "$SB/branch-file.json"; check "branch created with generated content" $?

# ---------- Scenario D: non-fast-forward race, retry must recover
echo; echo "=== D. push race: reject first push, land a real competing commit during the retry window"
new_sandbox D
printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xold"\n]\n' > "$ROOT/old.json"
seed_branch "$ROOT/old.json"
# hook: reject the orb's first push only; everything after passes
cat > "$SB/origin.git/hooks/pre-receive" <<HOOK
#!/bin/sh
if [ ! -f "$SB/.race-done" ]; then
  touch "$SB/.race-done"
  echo "simulated rejection of first push" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$SB/origin.git/hooks/pre-receive"
printf '[\n  "0xaaa",\n  "0xbbb",\n  "0xold",\n  "0xnew"\n]\n' > "$SB/work/list.json"
# run the orb script in the background; its retry sleeps 5s after the rejection
( run_script > "$SB/rc" ) &
SCRIPT_PID=$!
# wait for the first push to be rejected, then land a genuine competing commit
for i in $(seq 1 100); do [ -f "$SB/.race-done" ] && break; sleep 0.1; done
git clone -q "$SB/origin.git" "$SB/racer" 2>/dev/null
git -C "$SB/racer" config user.email r@r && git -C "$SB/racer" config user.name racer
git -C "$SB/racer" checkout -q updated-addresses
echo racer > "$SB/racer/racer.txt"
git -C "$SB/racer" add . && git -C "$SB/racer" commit -qm "racer commit" && git -C "$SB/racer" push -q origin updated-addresses
wait "$SCRIPT_PID"
check "script exits 0 after retry" "$(cat "$SB/rc")"
grep -q "Push attempt 1 failed" "$SB/out.log"; check "first push rejected, retry triggered" $?
branch_file; grep -q "0xnew" "$SB/branch-file.json"; check "final branch file has generated content" $?
git -C "$SB/work" log origin/updated-addresses --format=%s > "$SB/log.txt"; grep -q "racer commit" "$SB/log.txt"; check "racer commit survives (rebased on top, not clobbered)" $?
git -C "$SB/work" show origin/updated-addresses:racer.txt >/dev/null 2>&1; check "racer's file change survives on the branch" $?

echo; echo "================================"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
