#!/bin/sh
set -eu

usage() {
  cat >&2 <<'EOF'
Usage:
  sh install_with_skills_cli.sh <source> [skills add options...]

Examples:
  sh install_with_skills_cli.sh vercel-labs/skills --skill find-skills
  sh install_with_skills_cli.sh https://github.com/vercel-labs/skills --skill find-skills
  sh install_with_skills_cli.sh claude-office-skills/skills@excel-automation
EOF
  exit 1
}

[ $# -ge 1 ] || usage

SOURCE="$1"
shift

for arg in "$@"; do
  case "$arg" in
    -g|--global|-a|--agent|--all|-l|--list)
      echo "Do not pass $arg. This wrapper controls the Omnibot install target." >&2
      exit 2
      ;;
  esac
done

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
OMNIBOT_ROOT="${OMNIBOT_ROOT:-$WORKSPACE_ROOT/.omnibot}"
TARGET_ROOT="${OMNIBOT_SKILLS_ROOT:-$OMNIBOT_ROOT/skills}"
TMP_BASE="${TMPDIR:-/tmp}/omnibot-skills-cli.$$"
STAGE_DIR="$TMP_BASE/project"
STAGED_SKILLS_DIR="$STAGE_DIR/.agents/skills"

cleanup() {
  rm -rf "$TMP_BASE"
}

trap cleanup EXIT INT TERM

mkdir -p "$STAGE_DIR" "$TARGET_ROOT"

cd "$STAGE_DIR"
npx -y skills add "$SOURCE" -a universal --copy -y "$@"

[ -d "$STAGED_SKILLS_DIR" ] || {
  echo "Skills CLI did not produce $STAGED_SKILLS_DIR" >&2
  exit 3
}

installed_count=0

for skill_dir in "$STAGED_SKILLS_DIR"/*; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_id=$(basename "$skill_dir")
  target_dir="$TARGET_ROOT/$skill_id"
  if [ -e "$target_dir" ]; then
    echo "Target skill already exists: $target_dir" >&2
    exit 4
  fi
  installed_count=$((installed_count + 1))
done

[ "$installed_count" -gt 0 ] || {
  echo "No staged skills were found under $STAGED_SKILLS_DIR" >&2
  exit 5
}

copied_count=0

for skill_dir in "$STAGED_SKILLS_DIR"/*; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_id=$(basename "$skill_dir")
  target_dir="$TARGET_ROOT/$skill_id"
  cp -R "$skill_dir" "$target_dir"
  copied_count=$((copied_count + 1))
  echo "Installed $skill_id -> $target_dir"
done

[ "$copied_count" -eq "$installed_count" ] || {
  echo "Copied $copied_count skills, expected $installed_count" >&2
  exit 6
}

echo "Done. Re-run skills_list in Omnibot to verify the new skill entries."
