#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <version>

Examples:
  $0 1.0.0
  $0
EOF
}

while getopts ":h" opt; do
    case $opt in
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

INPUT="${1:-}"

for cmd in gh git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required"
        exit 1
    fi
done

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh must be authenticated"
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Error: must be on main branch (currently on $BRANCH)"
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree must be clean"
    exit 1
fi

git fetch origin main --tags --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "Error: local main is not up to date with origin/main"
    echo "  local:  $LOCAL"
    echo "  remote: $REMOTE"
    exit 1
fi

PREV=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -n1)

if [[ -z "$INPUT" ]]; then
    echo ""
    if [[ -n "$PREV" ]]; then
        echo "Current release: ${PREV}"
    else
        echo "Current release: (none)"
    fi
    echo ""
    read -rp "Enter new version: " INPUT
fi

if [[ -z "$INPUT" ]]; then
    echo "Error: version cannot be empty"
    exit 1
fi

INPUT="${INPUT#v}"
if [[ ! "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be a valid semver (e.g. 1.0.0)"
    exit 1
fi

VERSION="v${INPUT}"
MAJOR_TAG="v${INPUT%%.*}"

if git tag -l "$VERSION" | grep -q "^${VERSION}$"; then
    echo "Error: tag $VERSION already exists"
    exit 1
fi

if gh release view "$VERSION" >/dev/null 2>&1; then
    echo "Error: release $VERSION already exists"
    exit 1
fi

echo ""
echo "=== Release Summary ==="
if [[ -n "$PREV" ]]; then
    echo "  Previous release: ${PREV}"
else
    echo "  Previous release: (none)"
fi
echo "  Version:          ${VERSION}"
echo "  Release tag:      ${VERSION}"
echo "  Moving major tag: ${MAJOR_TAG}"
echo "  Commit:           $(git rev-parse --short HEAD)"
echo "  Branch:           main"
echo ""
echo "  Consumers can pin:"
echo "    Gaucho-Racing/vault-pull-secrets@${VERSION}"
echo "    Gaucho-Racing/vault-pull-secrets@${MAJOR_TAG}"
echo ""
read -rp "Proceed? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

git tag "$VERSION" "$LOCAL"
git tag -f "$MAJOR_TAG" "$LOCAL"
git push origin "$VERSION"
git push --force origin "$MAJOR_TAG"

gh release create "$VERSION" \
    --target "$LOCAL" \
    --title "$VERSION" \
    --generate-notes

echo ""
echo "Done. ${VERSION} released and ${MAJOR_TAG} now points to $(git rev-parse --short HEAD)."
