#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

print_header() {
    printf '\n[%s]\n' "$1"
}

fail() {
    status=1
    printf '%s\n' "$1"
}

print_header "banned production patterns"
if ! rg -n 'allow\(dead_code\)|unreachable!\(|todo!\(|dbg!\(|println!\(|eprintln!\(' src -g '*.rs'; then
    printf 'clean\n'
fi

print_header "module docs"
while IFS= read -r file; do
    first_meaningful_line="$(awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#\!/ { next }
        /^[[:space:]]*#\[/ { next }
        { print; exit }
    ' "$file")"

    if [[ ! "$first_meaningful_line" =~ ^//! ]]; then
        fail "missing module doc: ${file#./}"
    fi
done < <(find src -type f -name '*.rs' | sort)

print_header "public item docs"
while IFS= read -r file; do
    awk -v file="$file" '
        function flush_public_item() {
            if (pending_public != "" && doc_ready == 0) {
                printf "missing public doc: %s:%d: %s\n", file, pending_line, pending_public;
                missing = 1;
            }
            pending_public = "";
            pending_line = 0;
            doc_ready = 0;
        }

        /^[[:space:]]*\/\/\// {
            doc_ready = 1;
            next;
        }

        /^[[:space:]]*#\[/ {
            next;
        }

        /^pub([[:space:]]|$)/ {
            if (pending_public != "") {
                flush_public_item();
            }
            pending_public = $0;
            pending_line = NR;
            next;
        }

        /^[[:space:]]*$/ {
            next;
        }

        {
            flush_public_item();
        }

        END {
            flush_public_item();
            exit missing;
        }
    ' "$file" || status=1
done < <(find src -type f -name '*.rs' | sort)

print_header "cargo checks"
cargo fmt --all --check
cargo check
cargo test

exit "$status"
