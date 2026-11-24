#!/bin/sh
# Tests for git-pretend. Usage: test/run.sh [shell]   (default: sh; try dash, bash, zsh)
# Each test runs in a fresh repository in a temporary directory, with no user git config.
# shellcheck disable=SC1010 # `pretend done` passes git-pretend's subcommand, not the loop keyword
set -u

test_shell=${1:-sh}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
bin=$root/bin/git-pretend
tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-pretend-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export GIT_PAGER=cat LC_ALL=C

passed=0 failed=0 current=

pretend() { "$test_shell" "$bin" "$@"; }

check() { "$@" || fail "expected success: $*"; }
check_not() { if "$@"; then fail "expected failure: $*"; fi; }
check_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }

commit() {
	git add -A && git commit -q -m "$1"
	git rev-parse HEAD
}

# A repository with a short history on main:
#   c1: a.txt, b.txt, old.txt   c2: modify a, delete b, rename old->new, add dir/c.txt
#   c3: modify c
new_repo() {
	dir=$tmp/$1
	mkdir -p "$dir" && cd "$dir" || exit 1
	git init -q -b main
	printf 'a1\n' >a.txt
	printf 'b1\n' >b.txt
	printf 'old file\nwith lines\nso rename detection works\n' >old.txt
	c1=$(commit c1)
	printf 'a2\n' >a.txt
	rm b.txt
	git mv -k old.txt new.txt
	mkdir dir && printf 'c1\n' >dir/c.txt
	c2=$(commit c2)
	printf 'c2\n' >dir/c.txt
	c3=$(commit c3)
}

clean() { [ -z "$(git status --porcelain)" ]; }

run() {
	current=$1
	(
		"$1"
	) || true
	# Subshell failures are counted by the marker file below
	if [ -e "$tmp/failed.$1" ]; then failed=$((failed + 1)); else passed=$((passed + 1)); fi
}

# Tests run in subshells (each one cds into its own repo), so failures are reported via files
fail() {
	printf '  FAIL %s: %s\n' "$current" "$*"
	: >"$tmp/failed.$current"
	return 1
}

# --- tests ---------------------------------------------------------------------------------------

t_single_commit() {
	new_repo single
	pretend "$c2" >/dev/null || fail "pretend failed"
	check_eq "$(git rev-parse HEAD)" "$c1"
	check_not git symbolic-ref -q HEAD
	# Working tree is c2
	check_eq "$(cat a.txt)" "a2"
	check test ! -e b.txt
	check test -e new.txt
	check test ! -e old.txt
	# Nothing staged, every change unstaged, no untracked files (new ones are intent-to-add)
	check_eq "$(git diff --cached --name-only)" ""
	check_eq "$(git ls-files --others --exclude-standard)" ""
	check_eq "$(git diff --no-renames --name-status | sort | tr '\t\n' ' ,')" "A dir/c.txt,A new.txt,D b.txt,D old.txt,M a.txt,"
}

t_done_restores() {
	new_repo done
	pretend "$c2" >/dev/null
	out=$(pretend done) || fail "done failed"
	check_eq "$(git symbolic-ref --short HEAD)" "main"
	check_eq "$(git rev-parse HEAD)" "$c3"
	check clean
	check test ! -e "$(git rev-parse --absolute-git-dir)/pretend"
	case $out in *"Back on main."*) ;; *) fail "unexpected output: $out" ;; esac
}

t_two_args_and_ranges() {
	new_repo ranges
	pretend "$c1" "$c3" >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c1"
	check_eq "$(cat dir/c.txt)" "c2"
	pretend done >/dev/null

	pretend "$c1..$c3" >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c1"
	check_eq "$(cat dir/c.txt)" "c2"
	pretend done >/dev/null

	# An empty side means HEAD
	pretend "$c1.." >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c1"
	check_eq "$(git diff HEAD --stat | tail -1 | cut -c2-)" "$(git diff "$c1" "$c3" --stat | tail -1 | cut -c2-)"
	pretend done >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c3"
}

t_merge_base_range() {
	new_repo mergebase
	git switch -q -c feature "$c2"
	printf 'feature\n' >f.txt
	f1=$(commit f1)
	# main is at c3; main...feature starts at their merge base, c2
	pretend main... >/dev/null || fail "pretend failed"
	check_eq "$(git rev-parse HEAD)" "$c2"
	check_eq "$(git diff HEAD --name-only)" "f.txt"
	pretend done >/dev/null
	check_eq "$(git symbolic-ref --short HEAD)" "feature"
	check_eq "$(git rev-parse HEAD)" "$f1"
}

t_edits_are_saved_and_discarded() {
	new_repo edits
	pretend "$c2" >/dev/null
	printf 'edited\n' >a.txt
	printf 'scratch\n' >scratch.txt
	out=$(pretend done)
	check_eq "$(cat a.txt)" "a2" # back on main, whose a.txt is c2's
	check test -e scratch.txt     # untracked files are never deleted
	case $out in *"scratch.txt"*) ;; *) fail "new untracked file not listed: $out" ;; esac
	patch=$(ls "$(git rev-parse --absolute-git-dir)"/pretend-discarded/*.patch 2>/dev/null)
	check test -n "$patch"
	grep -q '^+edited$' "$patch" || fail "patch does not contain the edit"
}

t_refuses_dirty_tree() {
	new_repo dirty
	printf 'dirty\n' >>a.txt
	check_not pretend "$c2" 2>/dev/null
	check_eq "$(git rev-parse HEAD)" "$c3"
	check_eq "$(git symbolic-ref --short HEAD)" "main"
	# Untracked files alone are fine
	git checkout -q a.txt
	printf 'x\n' >untracked.txt
	pretend "$c2" >/dev/null || fail "untracked file blocked pretend"
	check test -e untracked.txt
	out=$(pretend done)
	case $out in *"untracked.txt"*) fail "pre-existing untracked file listed as new" ;; esac
}

t_refuses_twice() {
	new_repo twice
	pretend "$c2" >/dev/null
	check_not pretend "$c3" 2>/dev/null
	check_eq "$(git rev-parse HEAD)" "$c1"
}

t_root_commit() {
	new_repo root
	check_not pretend "$c1" 2>/dev/null
	check_eq "$(git symbolic-ref --short HEAD)" "main"
}

t_same_commit() {
	new_repo same
	check_not pretend "$c2" "$c2" 2>/dev/null
	check_not pretend bogus 2>/dev/null
	check clean
}

t_status() {
	new_repo status
	check_not pretend status >/dev/null
	check_eq "$(pretend status --porcelain)" ""
	pretend "$c2" >/dev/null
	check pretend status >/dev/null
	porcelain=$(pretend status --porcelain)
	check_eq "$(printf '%s\n' "$porcelain" | sed -n 's/^base //p')" "$c1"
	check_eq "$(printf '%s\n' "$porcelain" | sed -n 's/^target //p')" "$c2"
	check_eq "$(printf '%s\n' "$porcelain" | sed -n 's/^prev-ref //p')" "refs/heads/main"
	# No arguments while pretending shows the status rather than the picker
	case $(pretend </dev/null) in *"Pretending you wrote"*) ;; *) fail "bare git pretend did not show status" ;; esac
}

t_status_short() {
	new_repo short
	check_not pretend status --short
	check_eq "$(pretend status --short)" ""
	pretend "$c2" >/dev/null
	check_eq "$(pretend status --short)" "main"
	pretend done >/dev/null
	# Started detached: the commit you will go back to
	git switch -q --detach "$c2"
	pretend "$c3" >/dev/null
	check_eq "$(pretend status --short)" "$(git rev-parse --short "$c2")"
	pretend done >/dev/null
}

t_readable_range_names() {
	new_repo names
	git switch -q -c feature "$c2"
	printf 'feature\n' >f.txt
	commit f1 >/dev/null
	# Named relative to the branch you started on
	case $(pretend main...) in *"Pretending you wrote feature~1..feature:"*) ;; *) fail "range not named after feature" ;; esac
	pretend done >/dev/null
	# A commit on no branch falls back to its short hash
	git switch -q --detach "$c1"
	printf 'loose\n' >loose.txt
	loose=$(commit loose)
	case $(pretend "$loose") in *"..$(git rev-parse --short "$loose"):"*) ;; *) fail "loose commit not shown as a hash" ;; esac
	pretend done >/dev/null
}

t_head_moved_outside() {
	new_repo moved
	pretend "$c2" >/dev/null
	git checkout -q -f main
	printf 'work in progress\n' >>a.txt
	pretend done >/dev/null 2>&1 || fail "done failed"
	# The branch and its uncommitted work were left alone
	check_eq "$(git rev-parse HEAD)" "$c3"
	check_eq "$(tail -1 a.txt)" "work in progress"
	check_not pretend status >/dev/null
}

t_commit_while_pretending() {
	new_repo commits
	pretend "$c2" >/dev/null
	git commit -q -am "made while pretending"
	stray=$(git rev-parse --short HEAD)
	out=$(pretend done) || fail "done failed"
	case $out in *"git branch <name> $stray"*) ;; *) fail "stray commit not reported: $out" ;; esac
	check_eq "$(git symbolic-ref --short HEAD)" "main"
	check clean
}

t_detached_start() {
	new_repo detached
	git switch -q --detach "$c2"
	pretend "$c3" >/dev/null
	pretend done >/dev/null
	check_not git symbolic-ref -q HEAD
	check_eq "$(git rev-parse HEAD)" "$c2"
}

t_from_subdirectory() {
	new_repo subdir
	cd dir || exit 1
	pretend "$c3" >/dev/null || fail "pretend from subdir failed"
	check_eq "$(git -C .. diff --name-only)" "dir/c.txt"
	pretend done >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c3"
}

t_ignored_but_tracked_file() {
	new_repo ignored
	printf '*.log\n' >.gitignore
	git add .gitignore && git commit -q -m ignore
	printf 'forced\n' >keep.log
	git add -f keep.log
	c5=$(commit "force-add ignored file")
	pretend "$c5" >/dev/null || fail "pretend failed"
	check_eq "$(git diff --name-only)" "keep.log"
	pretend done >/dev/null
	check clean
}

t_odd_paths() {
	new_repo odd
	printf 'x\n' >'with space.txt'
	printf 'y\n' >'tab	name.txt'
	c4=$(commit odd)
	pretend "$c4" >/dev/null
	check_eq "$(git ls-files --others --exclude-standard)" ""
	pretend done >/dev/null
	check clean
}

t_git_subcommand() {
	new_repo subcommand
	mkdir -p "$tmp/path"
	ln -sf "$bin" "$tmp/path/git-pretend"
	PATH=$tmp/path:$PATH git pretend "$c2" >/dev/null || fail "git pretend not found as a subcommand"
	PATH=$tmp/path:$PATH git pretend done >/dev/null
	check_eq "$(git rev-parse HEAD)" "$c3"
}

t_not_a_repo() {
	mkdir -p "$tmp/norepo" && cd "$tmp/norepo" || exit 1
	check_not pretend status 2>/dev/null
}

# --- runner --------------------------------------------------------------------------------------

printf 'git-pretend tests with %s\n' "$test_shell"
# Test names are single words, and a piped while loop would lose the counts in its subshell
# shellcheck disable=SC2013
for t in $(sed -n 's/^\(t_[a-z_]*\)() {$/\1/p' "$0"); do
	run "$t"
done
total=$((passed + failed))
printf '%d/%d passed\n' "$passed" "$total"
[ "$failed" -eq 0 ]
