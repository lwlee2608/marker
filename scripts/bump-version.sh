#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat >&2 <<'EOF'
Usage: scripts/bump-version.sh <patch|minor|major|x.y.z>

Examples:
  scripts/bump-version.sh patch
  scripts/bump-version.sh minor
  scripts/bump-version.sh 1.2.3
EOF
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

bump="$1"
current="$(node -p "require('./package.json').version")"

case "$bump" in
  patch|minor|major)
    IFS=. read -r major minor patch <<EOF
$current
EOF
    if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
      echo "Cannot auto-bump non-numeric version: $current" >&2
      exit 1
    fi
    case "$bump" in
      patch) patch=$((patch + 1)) ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      major) major=$((major + 1)); minor=0; patch=0 ;;
    esac
    next="$major.$minor.$patch"
    ;;
  *)
    if ! [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      usage
      exit 1
    fi
    next="$bump"
    ;;
esac

VERSION="$next" node <<'EOF'
const fs = require('fs');

const next = process.env.VERSION;

function replaceOnce(text, pattern, replacement, path) {
  if (!pattern.test(text)) {
    throw new Error(`Could not find version field in ${path}`);
  }
  return text.replace(pattern, replacement);
}

const pkgPath = 'package.json';
const tauriPath = 'src-tauri/tauri.conf.json';
const cargoPath = 'src-tauri/Cargo.toml';

let pkgText = fs.readFileSync(pkgPath, 'utf8');
let tauriText = fs.readFileSync(tauriPath, 'utf8');
let cargo = fs.readFileSync(cargoPath, 'utf8');

const pkg = JSON.parse(pkgText);
const tauri = JSON.parse(tauriText);
const cargoVersion = cargo.match(/^version = "([^"]+)"/m)?.[1];
const versions = new Set([pkg.version, tauri.version, cargoVersion]);
if (versions.size !== 1) {
  throw new Error(`Version fields are out of sync: package.json=${pkg.version}, tauri.conf.json=${tauri.version}, Cargo.toml=${cargoVersion}`);
}

pkgText = replaceOnce(pkgText, /^(\s*"version":\s*")[^"]+(",)$/m, `$1${next}$2`, pkgPath);
tauriText = replaceOnce(tauriText, /^(\s*"version":\s*")[^"]+(",)$/m, `$1${next}$2`, tauriPath);
cargo = replaceOnce(cargo, /^(version = ")[^"]+(")$/m, `$1${next}$2`, cargoPath);

fs.writeFileSync(pkgPath, pkgText);
fs.writeFileSync(tauriPath, tauriText);
fs.writeFileSync(cargoPath, cargo);

if (fs.existsSync('src-tauri/Cargo.lock')) {
  let lock = fs.readFileSync('src-tauri/Cargo.lock', 'utf8');
  lock = replaceOnce(
    lock,
    /(\[\[package\]\]\nname = "marker"\nversion = ")[^"]+(")/,
    `$1${next}$2`,
    'src-tauri/Cargo.lock',
  );
  fs.writeFileSync('src-tauri/Cargo.lock', lock);
}
EOF

echo "Bumped marker from $current to $next"
