# tmux-workflows.zsh
#
# Tmux-based workflow helpers for dev environments.
# Source this file from your .zshrc:
#   source /path/to/tmux-workflows.zsh
#
# Prerequisites: tmux, git, gh (GitHub CLI), claude (for review-pr)
#   jq        session/review metadata
#   fzf       the notes and resume pickers
#   python3   bin/notes-index, which joins the notes dirs to the knowledge base
#
# Workflows:
#   notes <topic>        open or create an investigation, routed against the KB
#   code <branch> -p …   start a coding session from one, in a linked worktree
#   review-pr <url>      review a PR in its own tmux window
#   wip                  what am I in the middle of
#   resume               reopen the tmux sessions a reboot took out
#   recall <terms>       which dir was I working on that in
#   notes-gc             prune notes dirs that hold nothing
#
# Optional:
#   GWT_SPARSE_CHECKOUT_CMD — function or command to run after creating a
#   worktree with a second argument, e.g.:
#     GWT_SPARSE_CHECKOUT_CMD='spt git:sparse reset && spt git:sparse add'
#   Called as: eval "$GWT_SPARSE_CHECKOUT_CMD $2"

# --- Config ---
# Override these in your .zshrc before sourcing this file.
: ${WORKSPACE:="$HOME/workspace"}
: ${NOTES_DIR:="$WORKSPACE/_notes"}
: ${REVIEWS_DIR:="$WORKSPACE/_reviews"}
: ${GWT_SPARSE_CHECKOUT_CMD:=""}

# Knowledge base that `notes` routes against, and the helpers that read it.
# Unset NOTES_KB to fall back to plain directory-name matching.
: ${NOTES_KB:="$WORKSPACE/notes-kb"}
: ${NOTES_BIN:="${DOTFILES:-$HOME/Projects/dotfiles}/bin"}
: ${NOTES_CACHE:="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-workflows/notes-routing.tsv"}
: ${NOTES_REDIRECTS:="${NOTES_CACHE:h}/notes-redirects.tsv"}

# Repo whose worktrees are created by `spt git:worktree` rather than plain git,
# so they inherit sparse checkout and get a Bazel output base. Also the repo
# `gfr` and `code` treat as the monorepo.
: ${MONOREPO_DIR:=""}

# How to fetch the monorepo: it has its own fetch path, and a plain
# `git pull --rebase` against it is slow enough to be unusable.
#   MONOREPO_FETCH_CMD='spt git:fetch-local'
: ${MONOREPO_FETCH_CMD:=""}

# Where the PR review workflow talks to GitHub. Point REVIEW_GH_HOST at a
# GitHub Enterprise hostname to review PRs there. REVIEW_DEFAULT_OWNER is the
# org assumed for review dirs that predate .review-meta.json; with it unset
# those dirs report "could not fetch PR status" rather than guessing an org.
: ${REVIEW_GH_HOST:="github.com"}
: ${REVIEW_DEFAULT_OWNER:=""}

# Worktrees live inside the repo they belong to, at <repo>/.worktrees/<branch>
# (slashes in the branch flattened to dashes). Nothing to manage but the repo
# itself, and a worktree's repo is its grandparent dir rather than something
# decoded out of a mangled directory name. Add `.worktrees/` to your global
# gitignore (see gitignore_global) so the repo never reads as dirty.
: ${WORKTREES_SUBDIR:=".worktrees"}

# --- Dependency check ---
for _twf_cmd in tmux git gh jq fzf rg; do
  if ! command -v "$_twf_cmd" &>/dev/null; then
    echo "tmux-workflows: missing required command: $_twf_cmd" >&2
  fi
done
unset _twf_cmd

# Builtins rather than forks: wip and resume ask for a directory mtime and
# the current time once per worktree.
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null

# --- Helpers ---

_git_default_branch() {
  local b
  b=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  echo "${b:-master}"
}

# --- Tmux session management ---

# Sets REPLY to the tmux session name for a checkout.
#
# The one place a session name is derived, because tat, gwt, code and resume
# all have to agree on it. They did not: two of them left the branch's slashes
# in, so `gwt you/PROJ-1-thing` and `code you/PROJ-1-thing` produced two
# different sessions for the same worktree, and both showed up in the chooser.
# Slashes and dots both flatten to dashes -- tmux treats a slash as ordinary in
# a session name but a colon-or-slash target is ambiguous to read, and dots
# break `-t` matching outright.
_tmux_session_name() {
  local name="$1"
  [[ -n "${2:-}" ]] && name="${1}--${2}"
  name="${name//\//-}"
  REPLY="${name//./-}"
}

# List tmux sessions, newest first, highlighting ones running processes
#
# The implementation is bin/tmux-sessions, because `prefix + s` needs the same
# list from inside tmux and a popup cannot call a zsh function.
tls() {
  local bin="${NOTES_BIN}/tmux-sessions"
  if [[ ! -x "$bin" ]]; then
    echo "tls: $bin not found"
    return 1
  fi
  "$bin" "$@"
}

# Attach to a tmux session by fuzzy name match
tatt() {
  local match
  match=$(tmux ls -F '#{session_name}' 2>/dev/null | grep -F "$1" | head -1)
  if [ -n "$match" ]; then
    tmux at -t "$match"
  else
    echo "No session matching '$1'"
    return 1
  fi
}

# Attach or create a tmux session named after the repo/branch
tat() {
  if [[ -n "$1" ]]; then
    cd "$1" || return 1
  fi
  local session_name
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local git_dir=$(cd "$(git rev-parse --git-dir)" && pwd)
    local git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
    local dirname=$(basename "$(dirname "$git_common_dir")")
    if [[ "$git_dir" != "$git_common_dir" ]]; then
      local branch=$(git rev-parse --abbrev-ref HEAD)
      _tmux_session_name "$dirname" "$branch"
    else
      _tmux_session_name "$dirname"
    fi
  else
    _tmux_session_name "${PWD##*/}"
  fi
  session_name=$REPLY
  if tmux ls 2>/dev/null | grep -q "^${session_name}:"; then
    if [[ -n "$TMUX" ]]; then
      tmux switch-client -t "$session_name"
    else
      tmux at -t "$session_name"
    fi
    return 0
  fi
  if [[ -n "$TMUX" ]]; then
    tmux new-session -d -s "$session_name" && tmux switch-client -t "$session_name"
  else
    tmux new -s "$session_name"
  fi
}

# --- Git worktrees ---

# Where a worktree for branch $2 of the repo at $1 belongs.
_worktree_path() { print -r -- "${1}/${WORKTREES_SUBDIR}/${2//\//-}"; }

# The main checkout, from anywhere inside a repo or any of its worktrees.
# --git-common-dir can come back relative, so resolve it from the dir asked
# about rather than from $PWD.
_main_repo_root() {
  local dir="${1:-$PWD}" common
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$dir" && cd "$common" && pwd) || return 1
  print -r -- "${common:h}"
}

# Whether $1 (default $PWD) is inside a worktree rather than a main checkout.
_in_worktree() { [[ "${1:-$PWD}" == */${WORKTREES_SUBDIR}/* ]]; }

# Every worktree on the machine: the repos in $WORKSPACE, plus $MONOREPO_DIR
# when it lives outside it.
_all_worktree_dirs() {
  local -a roots seen out
  roots=( "$WORKSPACE"/*(/N) )
  [[ -n "$MONOREPO_DIR" && -d "$MONOREPO_DIR" ]] && roots+=( "${MONOREPO_DIR:A}" )
  local r d
  for r in "${roots[@]}"; do
    (( ${seen[(I)${r:A}]} )) && continue
    seen+=( "${r:A}" )
    for d in "${r:A}/${WORKTREES_SUBDIR}"/*(/N); do out+=( "$d" ); done
  done
  (( ${#out} )) && print -rl -- "${out[@]}"
}

# Create or switch to a git worktree under <repo>/.worktrees
#
# Usage:
#   gwt <branch>                                       create worktree, attach tmux session
#   gwt <branch> --install                             + auto-install deps (npm/yarn/pnpm)
#   gwt <branch> -p "<prompt>"                         + open Claude Code with the given prompt
#   gwt <branch> -p path/to/prompt.md                  + read prompt from file
#   gwt <branch> -p "<prompt>" --safer                 + --permission-mode acceptEdits (auto-accept edits, still confirm shell)
#   gwt <branch> -p "<prompt>" --yolo                  + --dangerously-skip-permissions (bypass everything)
#   gwt <branch> -p "<prompt>" --model <name>          + --model <name> (e.g. sonnet, haiku) — cheaper for routine work
#   gwt <branch> --sparse                              + copy sparse checkout from default branch
#   gwt <branch> <sparse-token> [-p ... [--safer|--yolo] [--model <name>]]
#                                                      + apply $GWT_SPARSE_CHECKOUT_CMD
#   gwt                                                inside a feature branch: switch to its worktree
#
# --safer vs --yolo: --safer is the recommended default for feature work
# (auto-accepts file edits, still pauses on shell commands → fewer wasted
# iteration cycles). --yolo is right for tight scaffolding where you trust
# the agent to run anything.
gwt() {
  if _in_worktree; then
    echo "Already in a worktree"
    return 1
  fi
  local source_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$source_root" ]]; then
    echo "Not in a git repository"
    return 1
  fi
  local original_pwd="$PWD"
  local root=$(basename "$source_root")

  # Parse Claude-launch flags out of the arg list, leaving positional args.
  local prompt="" mode="" model="" install=0 sparse=0
  local -a positional
  positional=()
  while (( $# )); do
    case "$1" in
      -p|--prompt)
        if [[ -z "$2" ]]; then
          echo "gwt: -p|--prompt requires a value (string or file path)"
          return 1
        fi
        prompt="$2"
        shift 2
        ;;
      --yolo)
        mode="bypass"
        shift
        ;;
      --safer)
        mode="safer"
        shift
        ;;
      --model)
        if [[ -z "$2" ]]; then
          echo "gwt: --model requires a value (e.g. sonnet, haiku)"
          return 1
        fi
        model="$2"
        shift 2
        ;;
      --install)
        install=1
        shift
        ;;
      --sparse)
        sparse=1
        shift
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  set -- "${positional[@]}"

  if [[ ( -n "$mode" || -n "$model" ) && -z "$prompt" ]]; then
    echo "gwt: --yolo, --safer, and --model only apply with -p|--prompt"
    return 1
  fi

  if (( install )) && [[ -z "$1" ]]; then
    echo "gwt: --install only applies when creating a new worktree"
    return 1
  fi

  # Resolve prompt source: if it points at an existing file, read it; otherwise treat as literal.
  local prompt_text=""
  if [[ -n "$prompt" ]]; then
    if [[ -f "$prompt" ]]; then
      prompt_text=$(<"$prompt")
    else
      prompt_text="$prompt"
    fi
  fi

  local branch created=0
  if [[ -n "$1" ]]; then
    branch="$1"
    local dest=$(_worktree_path "$source_root" "$branch")
    git worktree add -b "$branch" "$dest" "$(_git_default_branch)" || return 1
    [[ ! -f "$source_root/.env" ]] || cp "$source_root/.env" "$dest/.env"
    cd "$dest" || return 1
    if [[ -n "$2" && -n "$GWT_SPARSE_CHECKOUT_CMD" ]]; then
      eval "$GWT_SPARSE_CHECKOUT_CMD $2" || return 1
    fi
    created=1
  else
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$branch" == "$(_git_default_branch)" ]]; then
      echo "On $branch — pass a branch name to create a new worktree"
      return 1
    fi
    local dest=$(_worktree_path "$source_root" "$branch")
    if [[ -d "$dest" ]]; then
      cd "$dest" || return 1
    else
      if [[ -n "$(git status --porcelain)" ]]; then
        echo "Working tree is not clean — commit or stash changes first"
        return 1
      fi
      git checkout "$(_git_default_branch)" || return 1
      git worktree add "$dest" "$branch" || return 1
      [[ ! -f "$source_root/.env" ]] || cp "$source_root/.env" "$dest/.env"
      cd "$dest" || return 1
      created=1
    fi
  fi

  if (( created && sparse )); then
    echo "→ Copying sparse checkout from $(_git_default_branch)..."
    spt git:sparse copy-from-branch "$(_git_default_branch)" || {
      echo "gwt: sparse checkout copy failed"
      cd "$original_pwd"
      return 1
    }
  fi

  if (( created && install )) && [[ -d "$source_root/node_modules" && -f "$dest/package.json" && ! -d "$dest/node_modules" ]]; then
    local pm=""
    if [[ -f "$dest/pnpm-lock.yaml" ]]; then pm="pnpm"
    elif [[ -f "$dest/yarn.lock" ]]; then pm="yarn"
    elif [[ -f "$dest/package-lock.json" ]]; then pm="npm"
    fi
    if [[ -n "$pm" ]]; then
      echo "→ Installing deps in $(basename "$dest") via $pm (source has node_modules)..."
      (cd "$dest" && "$pm" install) || \
        echo "gwt: $pm install failed — install manually"
    fi
  fi

  # Hand off to tmux.
  #
  # No-prompt mode: defer to `tat` — creates+attaches in one step (you're
  # launching ONE worktree, you want to be in it).
  #
  # Prompt mode: spin up a detached tmux session with Claude already running,
  # then return to where the user was. Lets you fire multiple `gwt -p` calls
  # in parallel without being teleported into each session. Attach later via
  # `tatt <fragment>` or `tmux attach -t <session>`.
  if [[ -z "$prompt_text" ]]; then
    tat
    cd "$original_pwd"
    return
  fi

  local session_name
  _tmux_session_name "$root" "$branch"
  session_name=$REPLY

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -c "$dest"
  fi

  # Pass the prompt to Claude via a temp file so we don't have to escape it for
  # tmux send-keys. The new shell evaluates "$(cat ...)" cleanly.
  local tmpfile
  tmpfile=$(mktemp -t "gwt-prompt-XXXXXX") || return 1
  print -r -- "$prompt_text" > "$tmpfile"

  local claude_flags=""
  case "$mode" in
    bypass) claude_flags+=" --dangerously-skip-permissions" ;;
    safer)  claude_flags+=" --permission-mode acceptEdits" ;;
  esac
  [[ -n "$model" ]] && claude_flags+=" --model $model"

  tmux send-keys -t "$session_name" "claude${claude_flags} \"\$(cat ${tmpfile})\" && rm -f ${tmpfile}" Enter

  # Return user to their original cwd; don't attach.
  cd "$original_pwd"
  echo "Worktree:    $dest"
  echo "Tmux:        $session_name (detached)"
  echo "Attach with: tatt $session_name   # or: tmux attach -t $session_name"
}

# --- Navigation ---

# cd into $WORKSPACE
ws() { cd "$WORKSPACE/${1:-.}"; }
# cd into a worktree of the current repo, or into .worktrees with no argument.
# Takes either the branch name or the flattened directory name.
wt() {
  local root
  root=$(_main_repo_root) || { echo "wt: not in a git repository"; return 1; }
  local base="${root}/${WORKTREES_SUBDIR}"
  if [[ -z "$1" ]]; then
    [[ -d "$base" ]] || { echo "wt: no worktrees in ${root:t}"; return 1; }
    cd "$base"
    return
  fi
  local dest
  for dest in "${base}/$1" "$(_worktree_path "$root" "$1")"; do
    [[ -d "$dest" ]] && { cd "$dest"; return; }
  done
  echo "wt: no such worktree in ${root:t}: $1"
  return 1
}

# --- GitHub ---

# Open the current repo in the browser
ghr() {
  local url
  url=$(git config --get remote.origin.url \
    | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//')
  ${OPEN_CMD:-open} "$url"
}

# Open the current branch's PR in the browser
ghp() {
  gh pr view --web 2>/dev/null \
    || echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
}

# --- Workflow: PR Reviews ---

_review_parse_url() {
  local url="$1"
  _rv_owner=$(echo "$url" | sed -E 's|https?://[^/]+/([^/]+)/.*|\1|')
  _rv_repo=$(echo "$url" | sed -E 's|.*/([^/]+)/pull/.*|\1|')
  _rv_number=$(echo "$url" | sed -E 's|.*/pull/([0-9]+).*|\1|')
}

_review_infer_from_dirname() {
  local dirname="$1"
  _rv_repo=$(echo "$dirname" | sed -E 's/--[0-9]+$//')
  _rv_number=$(echo "$dirname" | grep -oE '[0-9]+$')
  _rv_owner="$REVIEW_DEFAULT_OWNER"
}

# Review a PR in a dedicated tmux session with Claude Code
review-pr() {
  local url="$1"
  if [[ -z "$url" ]]; then
    echo "Usage: review-pr <PR-URL>"
    return 1
  fi

  local _rv_owner _rv_repo _rv_number
  _review_parse_url "$url"

  if [[ -z "$_rv_owner" || -z "$_rv_repo" || -z "$_rv_number" ]]; then
    echo "Could not parse owner, repo, and PR number from URL"
    return 1
  fi

  local dirname="${_rv_repo}--${_rv_number}"
  local dir="${REVIEWS_DIR}/${dirname}"
  mkdir -p "$dir"

  local head_commit
  head_commit=$(GH_HOST="$REVIEW_GH_HOST" gh api "repos/${_rv_owner}/${_rv_repo}/pulls/${_rv_number}" \
    --jq '.head.sha' 2>/dev/null || echo "unknown")

  local meta="${dir}/.review-meta.json"
  if [[ -f "$meta" ]]; then
    local prev_commit
    prev_commit=$(jq -r '.head_commit' "$meta")
    if [[ "$prev_commit" == "$head_commit" && "$head_commit" != "unknown" ]]; then
      echo "No new commits since last review (${head_commit:0:7})"
      return 0
    fi
    local tmp
    tmp=$(jq \
      --arg head "$head_commit" \
      --arg reviewed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.head_commit = $head | .reviewed_at = $reviewed' "$meta")
    printf '%s\n' "$tmp" > "$meta"
  else
    cat > "$meta" <<EOF
{
  "url": "${url}",
  "owner": "${_rv_owner}",
  "repo": "${_rv_repo}",
  "pr_number": ${_rv_number},
  "head_commit": "${head_commit}",
  "reviewed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "comments": []
}
EOF
  fi

  local session="pr-reviews"
  local window="${_rv_repo}--${_rv_number}"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$REVIEWS_DIR"
  fi

  if tmux list-windows -t "$session" -F '#{window_name}' | grep -qxF "$window"; then
    tmux select-window -t "${session}:${window}"
  else
    tmux new-window -t "$session" -n "$window" -c "$dir"
  fi

  tmux send-keys -t "${session}:${window}" \
    "claude --dangerously-skip-permissions --model claude-opus-5 '/review-pr $url'" Enter

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "${session}:${window}"
  else
    tmux attach-session -t "${session}:${window}"
  fi
}

# Show status of all tracked PR reviews
review-status() {
  setopt local_options typeset_silent no_xtrace no_verbose
  local reviews_dir="${REVIEWS_DIR}"
  if [[ ! -d "$reviews_dir" ]]; then
    echo "No reviews directory found"
    return 1
  fi

  local -a review_dirs=("$reviews_dir"/*/(:N))
  if (( ${#review_dirs[@]} == 0 )); then
    echo "No reviews found"
    return 0
  fi

  local total=${#review_dirs[@]} current=0
  _review_spinner() {
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while true; do
      printf '\r  %s %s' "${chars:$((i % ${#chars})):1}" "$1" >&2
      ((i++))
      sleep 0.08
    done
  }
  _review_spinner "Checking ${total} reviews..." &!
  local spin_pid=$!
  trap "kill $spin_pid 2>/dev/null; printf '\r\033[K' >&2" EXIT INT TERM

  local -a attention updated open approved merged closed
  local my_login
  my_login=$(GH_HOST="$REVIEW_GH_HOST" gh api user --jq '.login' 2>/dev/null)
  local found=0

  for dir in "${review_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    found=1
    local dirname=$(basename "$dir")
    local meta="${dir}.review-meta.json"

    local owner repo number head_commit="unknown" url=""
    if [[ -f "$meta" ]]; then
      owner=$(jq -r '.owner' "$meta")
      repo=$(jq -r '.repo' "$meta")
      number=$(jq -r '.pr_number' "$meta")
      head_commit=$(jq -r '.head_commit' "$meta")
      url=$(jq -r '.url' "$meta")
    else
      repo=$(echo "$dirname" | sed -E 's/--[0-9]+$//')
      number=$(echo "$dirname" | grep -oE '[0-9]+$')
      owner="$REVIEW_DEFAULT_OWNER"
      url="https://${REVIEW_GH_HOST}/${owner}/${repo}/pull/${number}"
    fi

    local pr_json
    pr_json=$(GH_HOST="$REVIEW_GH_HOST" gh api "repos/${owner}/${repo}/pulls/${number}" \
      --jq '{state: .state, merged: .merged, head: .head.sha, title: .title}' 2>/dev/null)

    if [[ -z "$pr_json" ]]; then
      attention+=("  ? ${dirname}  (could not fetch PR status)")
      continue
    fi

    local state current_head title is_merged
    state=$(echo "$pr_json" | jq -r '.state')
    is_merged=$(echo "$pr_json" | jq -r '.merged')
    current_head=$(echo "$pr_json" | jq -r '.head')
    title=$(echo "$pr_json" | jq -r '.title')

    local short_title="${title:0:60}"
    [[ ${#title} -gt 60 ]] && short_title="${short_title}…"

    if [[ "$is_merged" == "true" ]]; then
      merged+=("  $(printf '%-30s %s' "$dirname" "$short_title")" "    ${url}" "")
    elif [[ "$state" == "closed" ]]; then
      closed+=("  $(printf '%-30s %s' "$dirname" "$short_title")" "    ${url}" "")
    else
      local my_review_state=""
      if [[ -n "$my_login" ]]; then
        my_review_state=$(GH_HOST="$REVIEW_GH_HOST" gh api "repos/${owner}/${repo}/pulls/${number}/reviews" \
          --jq "[.[] | select(.user.login == \"${my_login}\")] | last | .state // empty" 2>/dev/null)
      fi

      local has_new_commits=0 reply_count=0

      if [[ "$head_commit" != "unknown" && "$head_commit" != "$current_head" ]]; then
        has_new_commits=1
      fi

      if [[ -f "$meta" ]] && jq -e '.comments | length > 0' "$meta" &>/dev/null; then
        local my_comment_ids
        my_comment_ids=$(jq -r '[.comments[].id] | join(",")' "$meta")
        local all_comments
        all_comments=$(GH_HOST="$REVIEW_GH_HOST" gh api "repos/${owner}/${repo}/pulls/${number}/comments" \
          --paginate --jq '[.[] | {id, in_reply_to_id, user: .user.login}]' 2>/dev/null)
        if [[ -n "$all_comments" ]]; then
          reply_count=$(echo "$all_comments" | jq --arg ids "$my_comment_ids" '
            ($ids | split(",") | map(tonumber)) as $mine |
            [.[] | select(.in_reply_to_id != null and (.in_reply_to_id | IN($mine[])))] | length
          ')
        fi
      fi

      if [[ "$my_review_state" == "APPROVED" ]]; then
        approved+=("    $(printf '%-28s %s' "$dirname" "$short_title")")
        approved+=("    ${url}" "")
      elif (( reply_count > 0 )); then
        local flags="${reply_count} replies"
        (( has_new_commits )) && flags+=", new commits"
        attention+=("  * $(printf '%-28s %-20s %s' "$dirname" "[$flags]" "$short_title")")
        attention+=("    ${url}" "")
      elif (( has_new_commits )); then
        updated+=("  ~ $(printf '%-28s %s' "$dirname" "$short_title")")
        updated+=("    ${url}" "")
      else
        open+=("    $(printf '%-28s %s' "$dirname" "$short_title")")
        open+=("    ${url}" "")
      fi
    fi
  done

  kill $spin_pid 2>/dev/null
  wait $spin_pid 2>/dev/null
  printf '\r\033[K' >&2
  trap - EXIT INT TERM

  if (( ! found )); then
    echo "No reviews found"
    return 0
  fi

  if (( ${#attention[@]} )); then
    echo "Needs attention:"
    printf '%s\n' "${attention[@]}"
    echo ""
  fi
  if (( ${#updated[@]} )); then
    echo "Updated:"
    printf '%s\n' "${updated[@]}"
    echo ""
  fi
  if (( ${#open[@]} )); then
    echo "Open:"
    printf '%s\n' "${open[@]}"
    echo ""
  fi
  if (( ${#approved[@]} )); then
    echo "Approved:"
    printf '%s\n' "${approved[@]}"
    echo ""
  fi
  if (( ${#merged[@]} )); then
    echo "Merged:"
    printf '%s\n' "${merged[@]}"
    echo ""
  fi
  if (( ${#closed[@]} )); then
    echo "Closed:"
    printf '%s\n' "${closed[@]}"
  fi
}

# Remove review dirs for merged/closed PRs
review-cleanup() {
  setopt local_options typeset_silent no_xtrace no_verbose
  local reviews_dir="${REVIEWS_DIR}"
  local -a to_remove

  for dir in "$reviews_dir"/*/; do
    [[ -d "$dir" ]] || continue
    local dirname=$(basename "$dir")
    local meta="${dir}.review-meta.json"

    local owner repo number
    if [[ -f "$meta" ]]; then
      owner=$(jq -r '.owner' "$meta")
      repo=$(jq -r '.repo' "$meta")
      number=$(jq -r '.pr_number' "$meta")
    else
      repo=$(echo "$dirname" | sed -E 's/--[0-9]+$//')
      number=$(echo "$dirname" | grep -oE '[0-9]+$')
      owner="$REVIEW_DEFAULT_OWNER"
    fi

    local pr_state
    pr_state=$(GH_HOST="$REVIEW_GH_HOST" gh api "repos/${owner}/${repo}/pulls/${number}" \
      --jq '"\(.state):\(.merged)"' 2>/dev/null)

    if [[ "$pr_state" == "closed:true" || "$pr_state" == "closed:false" ]]; then
      to_remove+=("$dirname")
    fi
  done

  if (( ! ${#to_remove[@]} )); then
    echo "No merged or closed reviews to clean up"
    return 0
  fi

  echo "Will remove ${#to_remove[@]} review(s):"
  printf '  %s\n' "${to_remove[@]}"
  echo ""
  read -q "?Proceed? [y/N] " || { echo; return 0; }
  echo ""

  for dirname in "${to_remove[@]}"; do
    tmux kill-window -t "pr-reviews:${dirname}" 2>/dev/null
    rm -rf "${reviews_dir}/${dirname}"
    echo "  removed ${dirname}"
  done
}

# --- Workflow: Notes ---
#
# A notes dir carries `.session.json`, mirroring the `.review-meta.json` that
# review-pr already writes. It is the join key between a scratch dir, the
# worktrees that investigation spawned, and the knowledge base topic it
# distills into. `notes-index` reads it; `code` and `/wrap` write to it.

# Normalize a free-text query into a directory name.
_notes_slug() {
  local s="${(L)*}"
  s="${s//[^a-z0-9._-]/-}"
  # Collapse separator runs and trim the ends: "distro api / episode status"
  # should slug to distro-api-episode-status, not distro-api--episode-status.
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"
  print -r -- "${s%-}"
}

_notes_session_init() {
  local dir="$1" slug="$2" topic="$3" question="$4"
  local meta="${dir}/.session.json"
  [[ -f "$meta" ]] && return 0
  command -v jq &>/dev/null || return 0
  jq -n \
    --arg slug "$slug" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg topic "$topic" \
    --arg question "$question" \
    '{slug: $slug, created: $created, topic: $topic, question: $question,
      worktrees: [], wrapped_at: null}' > "$meta"
}

# Set one top-level field. Writes via a temp file: jq cannot edit in place.
_notes_session_set() {
  local dir="$1" key="$2" value="$3"
  local meta="${dir}/.session.json"
  [[ -f "$meta" ]] || return 1
  command -v jq &>/dev/null || return 1
  local tmp
  tmp=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$meta") || return 1
  printf '%s\n' "$tmp" > "$meta"
}

# The routing table is regenerated only when something it derives from has
# changed -- python3 takes ~0.65s to start on a managed Mac, too slow to pay on
# every invocation. The staleness check itself is pure zsh.
_notes_cache_stale() {
  [[ -s "$NOTES_CACHE" ]] || return 0
  local f
  for f in "$NOTES_DIR" "$NOTES_KB/index.md" "$NOTES_KB"/topics/*.md(N) \
           "$NOTES_DIR"/*(/N) "$NOTES_DIR"/*/.session.json(N); do
    [[ "$f" -nt "$NOTES_CACHE" ]] && return 0
  done
  return 1
}

_notes_reindex() {
  [[ -x "$NOTES_BIN/notes-index" ]] || return 1
  mkdir -p "${NOTES_CACHE:h}" || return 1
  "$NOTES_BIN/notes-index" --fzf > "${NOTES_CACHE}.new" || return 1
  mv "${NOTES_CACHE}.new" "$NOTES_CACHE"
  # Old names of dirs that notes-merge folded into another.
  "$NOTES_BIN/notes-index" --redirects > "${NOTES_REDIRECTS}.new" \
    && mv "${NOTES_REDIRECTS}.new" "$NOTES_REDIRECTS"
}

# Resolve a query to one of:
#   <slug>          an existing scratch dir
#   +topic:<slug>   a new dir attached to that knowledge base topic
#   +create:<slug>  a new, unattached dir
#
# Candidates come from notes-index, which matches against the KB's topic slugs,
# frontmatter aliases and index hooks -- not just directory names. That is what
# makes `notes episode metadata` find `analytics-episode-calls`.
_notes_resolve() {
  local query="$*"
  local slug
  slug=$(_notes_slug "$query")
  [[ -n "$slug" ]] || return 1

  # An exact dir name is an answer, not a query. Never open a picker for it.
  if [[ -d "${NOTES_DIR}/${slug}" ]]; then
    print -r -- "$slug"
    return
  fi

  # Degrade to the old behaviour when the index or fzf is unavailable.
  if [[ ! -x "$NOTES_BIN/notes-index" ]] || ! command -v fzf &>/dev/null; then
    print -r -- "+create:${slug}"
    return
  fi

  _notes_cache_stale && { _notes_reindex || true }

  # A name that notes-merge absorbed still has to land somewhere sensible --
  # muscle memory outlives directory layout.
  if [[ -s "$NOTES_REDIRECTS" ]]; then
    local redirected
    redirected=$(awk -F'\t' -v s="$slug" '$1 == s { print $2; exit }' \
      "$NOTES_REDIRECTS")
    if [[ -n "$redirected" && -d "${NOTES_DIR}/${redirected}" ]]; then
      print -u2 -- "notes: ${slug} was merged into ${redirected}"
      print -r -- "$redirected"
      return
    fi
  fi

  if [[ ! -s "$NOTES_CACHE" ]]; then
    print -r -- "+create:${slug}"
    return
  fi

  local pick
  pick=$(
    {
      cat "$NOTES_CACHE"
      printf '+ %-30s %-26s %5s  %-9s %s\t%s\n' \
        "create unattached dir" "$slug" "" "[new]" \
        "no knowledge base topic — /wrap will route it later" \
        "+create:${slug}"
    } | fzf --height=~20 --reverse \
            --delimiter=$'\t' --with-nth=1 \
            --query="$query" --select-1 --exit-0 \
            --prompt='notes> ' \
            --header='enter: open · a [topic] row starts a new dir under that topic' \
            --preview="'$NOTES_BIN/notes-preview' {2}" \
            --preview-window='right,52%,wrap,border-left'
  ) || return 1

  [[ -n "$pick" ]] || return 1
  print -r -- "${pick##*$'\t'}"
}

# Open a notes directory in a dedicated tmux session
#
# Usage:
#   notes <topic>                       resolve against the KB, open or create
#   notes <topic> -q "<question>"       record what the session is actually asking
#   notes <topic> -t <kb-topic>         attach to a KB topic explicitly
#   notes --reindex                     rebuild the routing table now
notes() {
  local question="" topic=""
  local -a positional
  positional=()
  while (( $# )); do
    case "$1" in
      -q|--question)
        if [[ -z "$2" ]]; then echo "notes: -q requires a value"; return 1; fi
        question="$2"; shift 2 ;;
      -t|--topic)
        if [[ -z "$2" ]]; then echo "notes: -t requires a value"; return 1; fi
        topic="$2"; shift 2 ;;
      --reindex)
        _notes_reindex && echo "notes: reindexed $NOTES_CACHE"
        return ;;
      *)
        positional+=("$1"); shift ;;
    esac
  done
  set -- "${positional[@]}"

  if [[ -z "$*" ]]; then
    echo "Usage: notes <topic> [-q \"<question>\"] [-t <kb-topic>]"
    echo "       notes --reindex"
    return 1
  fi

  local resolved dirname
  resolved=$(_notes_resolve "$@") || return 1

  case "$resolved" in
    +topic:*)
      # New dir named from the query, attached to the chosen KB topic.
      topic="${resolved#+topic:}"
      dirname=$(_notes_slug "$@") ;;
    +create:*)
      dirname="${resolved#+create:}" ;;
    *)
      dirname="$resolved" ;;
  esac
  [[ -n "$dirname" ]] || return 1

  local dir="${NOTES_DIR}/${dirname}"
  mkdir -p "$dir" || return 1

  _notes_session_init "$dir" "$dirname" "$topic" "$question"
  # -q/-t given for a dir that already exists should update it, not be dropped.
  [[ -n "$question" ]] && _notes_session_set "$dir" question "$question"
  [[ -n "$topic" ]] && _notes_session_set "$dir" topic "$topic"

  local session="notes--${dirname}"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir"
  fi

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

# Prune notes dirs that hold nothing, and report the ones that only look empty
#
# `notes <topic>` creates a dir eagerly, so a session that wrote no files still
# leaves one behind -- and its name then pollutes every future match. A dir with
# no files but a substantial transcript is the opposite problem: real work that
# was never distilled. Those are listed, never deleted.
notes-gc() {
  local dry=0
  [[ "$1" == "--dry-run" || "$1" == "-n" ]] && dry=1

  if [[ ! -x "$NOTES_BIN/notes-index" ]] || ! command -v jq &>/dev/null; then
    echo "notes-gc: needs notes-index and jq"
    return 1
  fi

  local index
  index=$("$NOTES_BIN/notes-index" --json) || return 1

  # Three buckets. Only the first is ever deleted.
  #   prunable    -- nothing on disk, no transcript, and the KB does not
  #                  reference it. There is nothing to lose but the name.
  #   dangling    -- empty, but a KB **Scratch:** line points here. Removing it
  #                  would silently break that pointer, so report it instead and
  #                  let /kb-tidy decide.
  #   recoverable -- empty on disk but the transcript is substantial: real work
  #                  that was never distilled.
  local -a prunable dangling recoverable
  prunable=( ${(f)"$(print -r -- "$index" | jq -r '
    .dirs[]
    | select(.files == 0 and .transcripts == 0 and (.topics | length) == 0)
    | .slug')"} )
  dangling=( ${(f)"$(print -r -- "$index" | jq -r '
    .dirs[]
    | select(.files == 0 and .transcripts == 0 and (.topics | length) > 0)
    | "\(.slug)\t\(.topics | join(", "))"')"} )
  recoverable=( ${(f)"$(print -r -- "$index" | jq -r '
    .dirs[]
    | select(.files == 0 and .transcripts > 0 and .wrapped == false)
    | "\(.slug)\t\(.transcript_kb) KB\t\(.age)"')"} )

  if (( ${#dangling} )); then
    echo "Empty, but a knowledge base topic points here:"
    printf '  %s\n' "${dangling[@]}" | column -t -s $'\t'
    echo "  → left alone; /kb-tidy marks dead scratch paths"
    echo ""
  fi

  if (( ${#recoverable} )); then
    echo "Never distilled, and the transcript is the only artifact:"
    printf '  %s\n' "${recoverable[@]}" | column -t -s $'\t'
    echo "  → claude --resume in the dir, or /wrap --recover <slug>"
    echo ""
  fi

  if (( ! ${#prunable} )); then
    echo "Nothing to prune"
    return 0
  fi

  echo "Empty, no transcript, safe to remove (${#prunable}):"
  printf '  %s\n' "${prunable[@]}"
  echo ""

  if (( dry )); then
    echo "(dry run — nothing removed)"
    return 0
  fi

  read -q "?Remove ${#prunable} dir(s)? [y/N] " || { echo; return 0 }
  echo ""
  local slug
  for slug in "${prunable[@]}"; do
    # Refuse to touch anything that is not actually empty.
    if [[ -n "$(find "${NOTES_DIR}/${slug}" -type f ! -name '.DS_Store' \
                     ! -name '.session.json' -print -quit 2>/dev/null)" ]]; then
      echo "  skipped ${slug} (not empty)"
      continue
    fi
    tmux kill-session -t "notes--${slug}" 2>/dev/null
    rm -rf "${NOTES_DIR}/${slug}"
    echo "  removed ${slug}"
  done
  _notes_reindex
}

# --- Workflow: notes -> code handoff ---

# Resolve the notes dir for the current directory, if we are in one.
_notes_current_slug() {
  local dir="${PWD:A}" root="${NOTES_DIR:A}"
  [[ "$dir" == "$root"/* ]] || return 1
  local rest="${dir#$root/}"
  print -r -- "${rest%%/*}"
}

# Start a coding session from an investigation
#
# Creates a worktree, opens a detached tmux session with Claude Code already
# running, and links the two directions: the worktree gets the notes dir via
# --add-dir (so the coding session can read the investigation that produced it),
# and the notes dir records the worktree in .session.json.
#
# Usage, from inside a notes dir:
#   code <branch>                          worktree + tmux, no prompt
#   code <branch> -p "<task>"              + start Claude on the task
#   code <branch> -p "<task>" --safer      + auto-accept edits
#   code <branch> -p "<task>" --yolo       + skip all permission prompts
#   code <branch> -c <component> ...       monorepo: sparse-checkout components
#   code <branch> --repo <name>            repo under $WORKSPACE (default: monorepo)
#   code <branch> --notes <slug>           run from anywhere
code() {
  local branch="" prompt="" mode="" model="" repo="" notes_slug=""
  local -a components
  components=()
  local -a positional
  positional=()

  while (( $# )); do
    case "$1" in
      -p|--prompt)
        if [[ -z "$2" ]]; then echo "code: -p requires a value"; return 1; fi
        prompt="$2"; shift 2 ;;
      -c|--component)
        if [[ -z "$2" ]]; then echo "code: -c requires a value"; return 1; fi
        components+=("$2"); shift 2 ;;
      --repo)
        if [[ -z "$2" ]]; then echo "code: --repo requires a value"; return 1; fi
        repo="$2"; shift 2 ;;
      --notes)
        if [[ -z "$2" ]]; then echo "code: --notes requires a value"; return 1; fi
        notes_slug="$2"; shift 2 ;;
      --model)
        if [[ -z "$2" ]]; then echo "code: --model requires a value"; return 1; fi
        model="$2"; shift 2 ;;
      --safer) mode="safer"; shift ;;
      --yolo)  mode="bypass"; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  set -- "${positional[@]}"
  branch="$1"

  if [[ -z "$branch" ]]; then
    echo "Usage: code <branch> [-p \"<task>\"] [-c <component>] [--repo <name>]"
    echo "                     [--notes <slug>] [--safer|--yolo] [--model <m>]"
    return 1
  fi

  # These helpers and NOTES_DIR come from this file and the shell profile. A
  # non-interactive shell (Claude Code's snapshot, `zsh -c`) can have `code`
  # without them, in which case every path below silently evaluates to "" and
  # the session gets built in the wrong place while still reporting success.
  local _fn
  for _fn in _worktree_path _notes_session_init _notes_current_slug; do
    if (( ! $+functions[$_fn] )); then
      echo "code: required helper '$_fn' is not defined."
      echo "      source ${DOTFILES:-$HOME/Projects/dotfiles}/zsh/tmux-workflows.zsh first."
      return 1
    fi
  done
  if [[ -z "$NOTES_DIR" ]]; then
    echo "code: NOTES_DIR is not set — source your shell profile, or set it explicitly."
    return 1
  fi

  # Which investigation is this coding session coming out of?
  if [[ -z "$notes_slug" ]]; then
    notes_slug=$(_notes_current_slug) || {
      echo "code: not inside $NOTES_DIR — pass --notes <slug>"
      return 1
    }
  fi
  local notes_dir="${NOTES_DIR}/${notes_slug}"
  if [[ ! -d "$notes_dir" ]]; then
    echo "code: no such notes dir: $notes_dir"
    return 1
  fi

  # Which repo? Explicit flag, then the last repo this investigation used,
  # then the monorepo.
  local repo_root=""
  if [[ -n "$repo" ]]; then
    repo_root="${WORKSPACE}/${repo}"
  else
    if [[ -f "$notes_dir/.session.json" ]] && command -v jq &>/dev/null; then
      local remembered
      remembered=$(jq -r '(.worktrees // []) | last | .repo // empty' \
        "$notes_dir/.session.json" 2>/dev/null)
      [[ -n "$remembered" ]] && repo_root="${WORKSPACE}/${remembered}"
    fi
    [[ -z "$repo_root" && -n "$MONOREPO_DIR" ]] && repo_root="${MONOREPO_DIR:A}"
  fi

  if [[ -z "$repo_root" || ! -d "$repo_root/.git" ]]; then
    echo "code: no repo resolved (tried '${repo_root:-<none>}')"
    echo "      pass --repo <name> or set MONOREPO_DIR"
    return 1
  fi

  local repo_name="${repo_root:t}"
  local dest session_name
  _tmux_session_name "$repo_name" "$branch"
  session_name=$REPLY

  dest=$(_worktree_path "$repo_root" "$branch")
  if [[ -z "$dest" ]]; then
    echo "code: could not resolve a worktree path for '$branch'."
    return 1
  fi

  # Same destination either way; only the creation differs. The monorepo's
  # worktrees need sparse-checkout inheritance and a Bazel output base, which
  # only `spt git:worktree` sets up.
  local is_monorepo=0
  [[ -n "$MONOREPO_DIR" && "$repo_root" == "${MONOREPO_DIR:A}" ]] && is_monorepo=1

  # Components are repo-relative paths (s4p-core-cms/s4p-episode-metadata),
  # not bare directory names. `spt git:worktree add -c` accepts a name that
  # matches nothing, writes it as a top-level cone pattern and reports
  # "Worktree ready" — leaving a worktree with none of the code in it.
  if (( is_monorepo && ${#components[@]} )) && command -v spt &>/dev/null; then
    local -a known_components
    known_components=( ${(f)"$(cd "$repo_root" && spt git:sparse list-components 2>/dev/null)"} )
    if (( ${#known_components[@]} )); then
      local bad=0 c
      for c in "${components[@]}"; do
        if (( ${known_components[(Ie)$c]} == 0 )); then
          echo "code: unknown component '$c'"
          bad=1
        fi
      done
      if (( bad )); then
        echo "      components are <system>/<component> paths. List them with:"
        echo "        spt git:sparse list-components"
        return 1
      fi
    fi
  fi

  if [[ -d "$dest" ]]; then
    echo "code: worktree already exists: $dest"
  elif (( is_monorepo )); then
    local -a spt_args
    spt_args=( git:worktree add "$branch" "$dest" )
    local c
    for c in "${components[@]}"; do spt_args+=( -c "$c" ); done
    ( cd "$repo_root" && spt "${spt_args[@]}" ) || return 1
  else
    ( cd "$repo_root" && git worktree add -b "$branch" "$dest" \
        "$(cd "$repo_root" && _git_default_branch)" ) || return 1
    [[ ! -f "$repo_root/.env" ]] || cp "$repo_root/.env" "$dest/.env"
  fi

  # Belt and braces for the above: confirm the code is actually there.
  local _c _missing=0
  for _c in "${components[@]}"; do
    if [[ ! -d "$dest/$_c" ]]; then
      echo "code: component '$_c' is not present in the worktree"
      _missing=1
    fi
  done
  if (( _missing )); then
    echo "      fix in place with:"
    echo "        cd $dest && spt git:sparse add <component>..."
  fi

  # Link the worktree back to the investigation, for /wrap from either side.
  # Excluded locally rather than via .gitignore: it is per-worktree state, and
  # without this every linked worktree would read as dirty in wip(1).
  print -r -- "$notes_dir" > "$dest/.notes-link"
  local exclude_file
  exclude_file="$(git -C "$dest" rev-parse --git-path info/exclude 2>/dev/null)"
  if [[ -n "$exclude_file" ]]; then
    mkdir -p "${exclude_file:h}"
    grep -qxF '.notes-link' "$exclude_file" 2>/dev/null \
      || print -r -- '.notes-link' >> "$exclude_file"
  fi

  # ...and the investigation forward to the worktree. Every dir that predates
  # session metadata has no .session.json, so create it rather than silently
  # dropping the link.
  _notes_session_init "$notes_dir" "$notes_slug" "" ""
  if [[ -f "$notes_dir/.session.json" ]] && command -v jq &>/dev/null; then
    local tmp
    tmp=$(jq \
      --arg repo "$repo_name" \
      --arg branch "$branch" \
      --arg path "$dest" \
      --arg tmux "$session_name" \
      --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.worktrees = ((.worktrees // [])
         | map(select(.branch != $branch))
         + [{repo: $repo, branch: $branch, path: $path, tmux: $tmux,
             created: $created}])' \
      "$notes_dir/.session.json") \
      && printf '%s\n' "$tmp" > "$notes_dir/.session.json"
  fi

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -c "$dest"
  fi

  if [[ -z "$prompt" ]]; then
    echo "Worktree: $dest"
    echo "Notes:    $notes_dir"
    echo "Tmux:     $session_name (detached) — tatt $session_name"
    return 0
  fi

  # Read the prompt from a file if it points at one, matching gwt.
  local prompt_text="$prompt"
  [[ -f "$prompt" ]] && prompt_text=$(<"$prompt")

  # Pass the prompt through a temp file so it needs no tmux send-keys escaping.
  local tmpfile
  tmpfile=$(mktemp -t "code-prompt-XXXXXX") || return 1
  {
    print -r -- "This coding session comes out of an investigation. Its notes are in"
    print -r -- "${notes_dir} (available to you via --add-dir). Read what is"
    print -r -- "relevant there before starting — do not re-derive it."
    print -r -- ""
    print -r -- "Task:"
    print -r -- "$prompt_text"
  } > "$tmpfile"

  local claude_flags="--add-dir ${(q)notes_dir}"
  case "$mode" in
    bypass) claude_flags+=" --dangerously-skip-permissions" ;;
    safer)  claude_flags+=" --permission-mode acceptEdits" ;;
  esac
  [[ -n "$model" ]] && claude_flags+=" --model $model"

  tmux send-keys -t "$session_name" \
    "claude ${claude_flags} \"\$(cat ${tmpfile})\" && rm -f ${tmpfile}" Enter

  echo "Worktree: $dest"
  echo "Notes:    $notes_dir  (linked via --add-dir)"
  echo "Tmux:     $session_name (detached) — tatt $session_name"
}

# --- Workflow: where was I? ---

# Find where you were working, by searching what you said
#
#   recall dalhouse pool        directories whose transcripts mention all terms
#
# `notes` searches names and knowledge base hooks -- what a subject is called.
# This searches the transcripts -- what you actually said. Use it when the
# subject is clear but the directory is not.
recall() {
  if [[ -z "$1" ]]; then
    echo "Usage: recall <terms...>"
    echo "  e.g. recall dalhouse pool     # which dir was the pool tuning in?"
    return 1
  fi
  if [[ ! -x "$NOTES_BIN/notes-recall" ]]; then
    echo "recall: $NOTES_BIN/notes-recall not found"
    return 1
  fi
  "$NOTES_BIN/notes-recall" "$@"
}

# --- Workflow: what am I in the middle of? ---

# Sets REPLY to a human-readable age from an epoch timestamp.
#
# Every row is aged the same way, notes-index's own "today" included: the
# picker is answering "when did I last touch this", and two vocabularies for
# that in one column is just two columns.
_resume_age() {
  local secs=$(( EPOCHSECONDS - ${1:-0} ))
  (( secs < 0 )) && secs=0
  if (( secs < 3600 )); then
    REPLY="$(( secs / 60 ))m"
  elif (( secs < 86400 )); then
    REPLY="$(( secs / 3600 ))h"
  elif (( secs < 86400 * 14 )); then
    REPLY="$(( secs / 86400 ))d"
  else
    REPLY="$(( secs / (86400 * 7) ))w"
  fi
}

# Sets REPLY to when Claude was last run in a directory, or 0.
#
# A transcript dir is named after the path it was opened at, with /, _ and .
# all mapped to -. For a worktree that is the truest record of recent work: the
# checkout's own mtime does not move when a file three levels down is edited,
# and the last commit can be days older than the session still in progress.
_resume_transcript_mtime() {
  local p="${1#/}"
  p="${p//\//-}"; p="${p//_/-}"; p="${p//./-}"
  local -a t st
  t=( "$HOME/.claude/projects/-${p}"/*.jsonl(N.om[1]) )
  if (( ${#t} )) && zstat -A st +mtime "${t[1]}" 2>/dev/null; then
    REPLY=$st[1]
  else
    REPLY=0
  fi
}

# Everything in flight, one row per thing, most recently touched first.
#
# TSV: kind  session  cwd  live  ts  age  context  name  flags  link
#
#   kind     notes | wt | review
#   session  the tmux session name notes/code/review-pr would have used
#   live     1 when that session exists right now
#   ts       last activity, epoch seconds
#   context  knowledge base topic (notes) or repo (worktrees)
#   flags    unwrapped | dirty | merged | "<n> tracked"   (--rich only)
#   link     notes dir a worktree came out of, from .notes-link
#
# No field is ever empty -- "-" stands in -- so readers can split on tabs
# without losing columns.
#
# Nothing here runs git or python. Both were tried and both were unusable: a
# `git status` in a sparse monorepo worktree costs 0.6-20s, and twenty of them
# turned resume into a thirty-second hang. Everything below is stat and file
# reads, which is enough to answer the only question a picker asks -- what did
# I touch most recently -- in well under a second.
#
# What "touched" means, newest wins:
#   notes dirs  the dir, its newest file, the Claude transcript for its path
#   worktrees   the checkout, the gitdir's logs/HEAD (commits and checkouts),
#               the Claude transcript. Not .git/index -- `git status` rewrites
#               it, so it reads as activity even when nothing happened.
#
# --topics adds what only notes-index knows -- knowledge base topic, whether a
# dir was ever distilled -- for about 0.8s. --state adds what only git knows --
# dirty, merged -- for about a second per worktree, and several seconds for a
# worktree git has not looked at in a while. wip takes the first by default and
# the second only when asked for it.
#
# --days windows the notes dirs. Every worktree is always listed, because wip
# is an inventory of them; resume applies its own window on ts.
#
# Sets $_resume_stale as a side effect under --topics: notes dirs left
# undistilled from before the window, a backlog rather than work in flight.
_resume_candidates() {
  local days=7 topics=0 want_state=0
  while (( $# )); do
    case "$1" in
      --days)   days="${2:-7}"; shift 2 ;;
      --topics) topics=1; shift ;;
      --state)  want_state=1; shift ;;
      *) shift ;;
    esac
  done
  local cutoff=$(( EPOCHSECONDS - 86400 * days ))

  local -a live rows st f newest
  live=( ${(f)"$(tmux ls -F '#{session_name}' 2>/dev/null)"} )
  _resume_stale=0

  # One notes-index call answers topic and wrapped for every dir at once; the
  # rows below then join against it by slug.
  local -A topic_of wrapped_of
  local index=""
  if (( topics )) && [[ -x "$NOTES_BIN/notes-index" ]] && command -v jq &>/dev/null; then
    if index=$("$NOTES_BIN/notes-index" --json 2>/dev/null); then
      local s_ t_ w_
      while IFS=$'\t' read -r s_ t_ w_; do
        topic_of[$s_]="$t_"
        wrapped_of[$s_]="$w_"
      # No empty fields: read(1) treats runs of tabs as one delimiter, so an
      # empty topic would shift .wrapped into its place.
      done < <(print -r -- "$index" | jq -r '.dirs[]
        | [.slug,
           (if (.topic // "") == "" then "-" else .topic end),
           (if .wrapped then "1" else "0" end)] | @tsv')
      _resume_stale=$(print -r -- "$index" | jq --argjson days "$days" '[.dirs[]
        | select(.wrapped == false and .last_activity <= (now - 86400 * $days))
        | select(.files > 0 or .transcripts > 0)] | length')
    fi
  fi

  local d slug sess islive ts ctx flags
  for d in "$NOTES_DIR"/*(/N); do
    slug="${d:t}"
    # The reviews dir lives under NOTES_DIR but is not an investigation.
    [[ "${d:A}" == "${REVIEWS_DIR:A}" ]] && continue

    ts=0
    zstat -A st +mtime "$d" 2>/dev/null && ts=$st[1]
    newest=( "$d"/*(N.om[1]) )
    if (( ${#newest} )) && zstat -A st +mtime "${newest[1]}" 2>/dev/null; then
      (( st[1] > ts )) && ts=$st[1]
    fi
    _resume_transcript_mtime "$d"
    (( REPLY > ts )) && ts=$REPLY

    # A dir with no files and no transcript holds nothing -- notes(1) creates
    # them eagerly, so most of them are a name and nothing else.
    (( ${#newest} )) || [[ $REPLY -gt 0 ]] || continue

    sess="notes--${slug}"
    islive=0; (( ${live[(I)$sess]} )) && islive=1
    (( ts > cutoff )) || (( islive )) || continue

    ctx="${topic_of[$slug]:--}"; [[ -n "$ctx" ]] || ctx="-"
    flags="-"
    (( topics )) && [[ "${wrapped_of[$slug]}" != "1" ]] && flags="unwrapped"

    f=( "$ts" notes "$sess" "$d" "$islive" "$ts" "-" "$ctx" "$slug" "$flags" "-" )
    rows+=( "${(pj:\t:)f}" )
  done

  local gitdir head_ref br repo_of link state sortkey
  for d in ${(f)"$(_all_worktree_dirs)"}; do
    # <repo>/.worktrees/<name>, so the repo is two levels up -- no need to ask
    # git which checkout this belongs to.
    repo_of="${d:h:h:t}"

    gitdir=""
    if [[ -f "$d/.git" ]]; then
      gitdir="${$(<"$d/.git")#gitdir: }"
      [[ "$gitdir" == /* ]] || gitdir="${d}/${gitdir}"
    elif [[ -d "$d/.git" ]]; then
      gitdir="$d/.git"
    fi
    [[ -r "$gitdir/HEAD" ]] || continue

    head_ref="$(<"$gitdir/HEAD")"
    if [[ "$head_ref" == ref:* ]]; then
      br="${${head_ref#ref: }#refs/heads/}"
    else
      br="${head_ref[1,9]}"
    fi
    [[ -n "$br" ]] || continue

    ts=0
    zstat -A st +mtime "$d" 2>/dev/null && ts=$st[1]
    if [[ -r "$gitdir/logs/HEAD" ]] && zstat -A st +mtime "$gitdir/logs/HEAD" 2>/dev/null; then
      (( st[1] > ts )) && ts=$st[1]
    fi
    _resume_transcript_mtime "$d"
    (( REPLY > ts )) && ts=$REPLY

    link="-"
    [[ -f "$d/.notes-link" ]] && link="${$(<"$d/.notes-link"):t}"

    state="-"
    if (( want_state )); then
      if git -C "$d" merge-base --is-ancestor HEAD origin/HEAD 2>/dev/null; then
        state="merged"
      elif [[ -n "$(git --no-optional-locks -C "$d" status --porcelain -uno 2>/dev/null)" ]]; then
        state="dirty"
      fi
    fi

    _tmux_session_name "$repo_of" "$br"
    sess=$REPLY
    islive=0; (( ${live[(I)$sess]} )) && islive=1
    sortkey=$ts; [[ "$state" == dirty ]] && (( sortkey += 43200 ))

    f=( "$sortkey" wt "$sess" "$d" "$islive" "$ts" "-" \
        "$repo_of" "$br" "$state" "$link" )
    rows+=( "${(pj:\t:)f}" )
  done

  # One session holds every review, so there is one row for the lot of them.
  local -a review_dirs
  review_dirs=( "$REVIEWS_DIR"/*(/N) )
  if (( ${#review_dirs} )); then
    local newest_review=0
    for d in "${review_dirs[@]}"; do
      zstat -A st +mtime "$d" 2>/dev/null || continue
      (( st[1] > newest_review )) && newest_review=$st[1]
    done
    islive=0; (( ${live[(I)pr-reviews]} )) && islive=1
    f=( "$newest_review" review pr-reviews "$REVIEWS_DIR" "$islive" \
        "$newest_review" "-" "-" pr-reviews "${#review_dirs} tracked" "-" )
    rows+=( "${(pj:\t:)f}" )
  fi

  (( ${#rows} )) || return 0

  # Ages are filled in here rather than at each source, so notes dirs and
  # worktrees are dated by the same clock. The leading sort key goes away
  # with the cut.
  local row
  local -a filled
  for row in "${rows[@]}"; do
    f=( "${(@ps:\t:)row}" )
    _resume_age "$f[6]"
    f[7]=$REPLY
    filled+=( "${(pj:\t:)f}" )
  done
  print -rl -- "${filled[@]}" | sort -t$'\t' -k1,1nr | cut -f2-
}

# One screen: live notes sessions, worktrees and what they came from, and
# anything never distilled. Reviews have their own status command; this counts
# them and points at it rather than re-running dozens of API calls.
#
#   wip            recency, topics, and what is undistilled
#   wip --state    + dirty and merged, at a git status per worktree
wip() {
  if [[ ! -x "$NOTES_BIN/notes-index" ]] || ! command -v jq &>/dev/null; then
    echo "wip: needs notes-index and jq"
    return 1
  fi

  # --state costs a git status per worktree, which in the monorepo is seconds
  # each. Off by default: the columns it fills are worth asking for, not worth
  # waiting for every time.
  local -a args
  args=( --days 7 --topics )
  [[ "$1" == "--state" || "$1" == "-s" ]] && args+=( --state )

  local -a rows out
  rows=( ${(f)"$(_resume_candidates "${args[@]}")"} )

  # In flight means: touched in the last week, or has a live tmux session.
  # Everything unwrapped regardless of age is a backlog, not a WIP list -- it
  # gets counted at the end instead of listed.
  echo "notes"
  out=( ${(f)"$(print -rl -- "${rows[@]}" | awk -F'\t' -v OFS='\t' '
    $1 == "notes" { print ($4 == "1" ? "⚡" : "  "), $8, $7, $6,
                          ($9 == "-" ? "" : toupper($9)) }')"} )
  if (( ! ${#out} )); then
    echo "  (nothing recent)"
  else
    print -rl -- "${out[@]}" | column -t -s $'\t'
  fi
  (( _resume_stale > 0 )) \
    && echo "  + ${_resume_stale} older, never distilled — notes-gc"
  echo ""

  echo "worktrees"
  out=( ${(f)"$(print -rl -- "${rows[@]}" | awk -F'\t' -v OFS='\t' '
    $1 == "wt" { print ($4 == "1" ? "⚡" : "  "), $7, $8, $10,
                       ($9 == "-" ? "" : $9) }')"} )
  if (( ! ${#out} )); then
    echo "  (none)"
  else
    print -rl -- "${out[@]}" | column -t -s $'\t'
  fi
  echo ""

  local -a review_dirs
  review_dirs=( "$REVIEWS_DIR"/*(/N) )
  echo "reviews: ${#review_dirs} tracked — run review-status for detail"
}

# --- Workflow: back from a restart ---

# Reopen the tmux sessions a reboot took out
#
# Derived rather than restored: the candidates are the notes dirs, worktrees
# and reviews that were actually active recently, so nothing has to be saved
# on the way down, a crash loses nothing, and work you have since abandoned
# never comes back. Sessions are created detached, at the right directory,
# with nothing running in them -- what you want back is the context, and the
# processes you left behind were mid-thought anyway.
#
# Session names match what notes, code and review-pr would have used, so a
# reopened session is the same session as far as every other command here is
# concerned. Anything already open is filtered out: safe to re-run any time.
#
# Usage:
#   resume                  pick from what was active in the last 7 days
#   resume --days 14        widen the window
#   resume -n               print what it would create, create nothing
#   resume -a               attach to the first session afterwards
resume() {
  local days=7 dry=0 attach=0
  while (( $# )); do
    case "$1" in
      --days)
        if [[ -z "$2" ]]; then echo "resume: --days requires a value"; return 1; fi
        days="$2"; shift 2 ;;
      -n|--dry-run) dry=1; shift ;;
      -a|--attach)  attach=1; shift ;;
      -h|--help)
        echo "Usage: resume [--days N] [-n|--dry-run] [-a|--attach]"
        return 0 ;;
      *) echo "resume: unknown option: $1"; return 1 ;;
    esac
  done

  if ! command -v fzf &>/dev/null; then
    echo "resume: needs fzf"
    return 1
  fi

  # Live sessions are already back. The merged check only bites when the rows
  # carry state, which the fast path does not ask for: hiding finished
  # worktrees is not worth a git status each. They age out of the window on
  # their own, and worktree-cleanup.sh is what actually removes them.
  local -a cands
  cands=( ${(f)"$(_resume_candidates --days "$days" \
    | awk -F'\t' -v cutoff=$(( EPOCHSECONDS - 86400 * days )) \
        '$4 == "0" && $9 != "merged" && $5 + 0 >= cutoff')"} )

  if (( ! ${#cands} )); then
    echo "resume: nothing to reopen"
    return 0
  fi

  # What tells these apart is the tail of the name, not the head: branches
  # cut from one ticket share a long prefix and differ in their last word.
  # So the column is wide, and what does not fit is cut off the front.
  local row kind sess cwd live ts age ctx name flags link detail line
  local -a menu parts
  for row in "${cands[@]}"; do
    IFS=$'\t' read -r kind sess cwd live ts age ctx name flags link <<< "$row"
    (( ${#name} > 50 )) && name="…${name[-49,-1]}"
    parts=()
    [[ "$ctx"   != "-" ]] && parts+=( "$ctx" )
    [[ "$flags" != "-" ]] && parts+=( "$flags" )
    [[ "$link"  != "-" ]] && parts+=( "notes: $link" )
    detail="${(j: · :)parts}"
    printf -v line '%-6s  %-50s  %4s  %s\t%s\t%s\t%s' \
      "$kind" "$name" "$age" "$detail" "$kind" "$sess" "$cwd"
    menu+=( "$line" )
  done

  local out
  out=$(print -rl -- "${menu[@]}" \
    | fzf --multi --height=~20 --reverse \
          --delimiter=$'\t' --with-nth=1 \
          --prompt='resume> ' \
          --header='tab: mark · enter: open the sessions (nothing runs in them)' \
          --preview="'$NOTES_BIN/resume-preview' {2} {4}" \
          --preview-window='right,52%,wrap,border-left') || return 1
  [[ -n "$out" ]] || return 1

  local disp
  local -a created
  while IFS=$'\t' read -r disp kind sess cwd; do
    [[ -n "$sess" && -d "$cwd" ]] || continue
    if (( dry )); then
      printf 'would open   %-40s %s\n' "$sess" "$cwd"
      continue
    fi
    # =name so a session whose name prefixes another is not mistaken for it.
    tmux has-session -t "=$sess" 2>/dev/null && continue
    tmux new-session -d -s "$sess" -c "$cwd" || continue
    created+=( "$sess" )
  done <<< "$out"

  (( ${#created} )) || return 0
  echo ""
  tls

  if (( attach )); then
    if [[ -n "$TMUX" ]]; then
      tmux switch-client -t "=${created[1]}"
    else
      tmux attach-session -t "=${created[1]}"
    fi
  fi
}

# --- Tab completion ---

_tmux_workflows_ws() { _path_files -W "$WORKSPACE" -/ }
_tmux_workflows_wt() {
  local root
  root=$(_main_repo_root 2>/dev/null) || return
  _path_files -W "${root}/${WORKTREES_SUBDIR}" -/
}

# Existing scratch dirs plus knowledge base topic slugs: typing a topic name
# should reach it even when no dir is named that yet.
_tmux_workflows_notes() {
  local -a dirs topics
  dirs=( "$NOTES_DIR"/*(/N:t) )
  topics=( "$NOTES_KB"/topics/*.md(N:t:r) )
  _describe -t dirs 'scratch dir' dirs
  _describe -t topics 'kb topic' topics
}

_tmux_workflows_init_completions() {
  compdef _tmux_workflows_ws ws
  compdef _tmux_workflows_wt wt
  compdef _tmux_workflows_ws tat
  compdef _tmux_workflows_notes notes
  add-zsh-hook -d precmd _tmux_workflows_init_completions
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _tmux_workflows_init_completions
