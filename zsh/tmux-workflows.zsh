# tmux-workflows.zsh
#
# Tmux-based workflow helpers for dev environments.
# Source this file from your .zshrc:
#   source /path/to/tmux-workflows.zsh
#
# Prerequisites: tmux, git, gh (GitHub CLI), claude (for review-pr)
#   jq        session/review metadata
#   fzf       the notes picker
#   python3   bin/notes-index, which joins the notes dirs to the knowledge base
#
# Workflows:
#   notes <topic>        open or create an investigation, routed against the KB
#   code <branch> -p …   start a coding session from one, in a linked worktree
#   review-pr <url>      review a PR in its own tmux window
#   wip                  what am I in the middle of
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
: ${WORKTREES_DIR:="$HOME/worktrees"}
: ${NOTES_DIR:="$WORKSPACE/_notes"}
: ${REVIEWS_DIR:="$NOTES_DIR/reviews"}
: ${GWT_SPARSE_CHECKOUT_CMD:=""}

# Knowledge base that `notes` routes against, and the helpers that read it.
# Unset NOTES_KB to fall back to plain directory-name matching.
: ${NOTES_KB:="$WORKSPACE/notes-kb"}
: ${NOTES_BIN:="${DOTFILES:-$HOME/Projects/dotfiles}/bin"}
: ${NOTES_CACHE:="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-workflows/notes-routing.tsv"}

# Repo whose worktrees are managed by `spt git:worktree` rather than plain git,
# so they inherit sparse checkout and get a Bazel output base.
: ${MONOREPO_DIR:=""}

# --- Dependency check ---
for _twf_cmd in tmux git gh jq fzf; do
  if ! command -v "$_twf_cmd" &>/dev/null; then
    echo "tmux-workflows: missing required command: $_twf_cmd" >&2
  fi
done
unset _twf_cmd

# --- Helpers ---

_git_default_branch() {
  local b
  b=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  echo "${b:-master}"
}

# --- Tmux session management ---

# List tmux sessions, highlighting ones running processes
tls() {
  tmux ls -F '#{session_name}' 2>/dev/null | while read -r session; do
    procs=$(tmux list-windows -t "$session" -F '#{pane_current_command}' \
      | grep -v '^zsh$' | tr '\n' ' ')
    if [[ -n "$procs" ]]; then
      echo "⚡ $session: $procs"
    else
      echo "  $session"
    fi
  done
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
      session_name="${dirname}--${branch}"
    else
      session_name=$dirname
    fi
  else
    session_name=${PWD##*/}
  fi
  session_name=${session_name//./-}
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

# Create or switch to a git worktree in $WORKTREES_DIR
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
  if [[ "$PWD" == *"/worktrees/"* ]]; then
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
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
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
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
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

  # Match tat's session naming convention: dirname--branch with dots → dashes.
  local session_name="${root}--${branch}"
  session_name=${session_name//./-}

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
# cd into $WORKTREES_DIR
wt() { cd "$WORKTREES_DIR/${1:-.}"; }

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
  _rv_owner="spotify"
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
  head_commit=$(GH_HOST=ghe.spotify.net gh api "repos/${_rv_owner}/${_rv_repo}/pulls/${_rv_number}" \
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
  my_login=$(GH_HOST=ghe.spotify.net gh api user --jq '.login' 2>/dev/null)
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
      owner="spotify"
      url="https://ghe.spotify.net/${owner}/${repo}/pull/${number}"
    fi

    local pr_json
    pr_json=$(GH_HOST=ghe.spotify.net gh api "repos/${owner}/${repo}/pulls/${number}" \
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
        my_review_state=$(GH_HOST=ghe.spotify.net gh api "repos/${owner}/${repo}/pulls/${number}/reviews" \
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
        all_comments=$(GH_HOST=ghe.spotify.net gh api "repos/${owner}/${repo}/pulls/${number}/comments" \
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
      owner="spotify"
    fi

    local pr_state
    pr_state=$(GH_HOST=ghe.spotify.net gh api "repos/${owner}/${repo}/pulls/${number}" \
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
  session_name="${repo_name}--${branch//\//-}"
  session_name=${session_name//./-}

  # The monorepo's worktrees need sparse-checkout inheritance and a Bazel
  # output base, which only `spt git:worktree` sets up.
  local is_monorepo=0
  [[ -n "$MONOREPO_DIR" && "$repo_root" == "${MONOREPO_DIR:A}" ]] && is_monorepo=1

  if (( is_monorepo )); then
    dest="${repo_root}/.worktrees/${branch//\//-}"
  else
    dest="${WORKTREES_DIR}/${repo_name}--${branch//\//-}"
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

# --- Workflow: what am I in the middle of? ---

# One screen: live notes sessions, worktrees and what they came from, and
# anything never distilled. Reviews have their own status command; this counts
# them and points at it rather than re-running dozens of API calls.
wip() {
  if [[ ! -x "$NOTES_BIN/notes-index" ]] || ! command -v jq &>/dev/null; then
    echo "wip: needs notes-index and jq"
    return 1
  fi

  local index
  index=$("$NOTES_BIN/notes-index" --json) || return 1

  local -a live
  live=( ${(f)"$(tmux ls -F '#{session_name}' 2>/dev/null)"} )
  local marker

  # In flight means: touched in the last week, or has a live tmux session.
  # Everything unwrapped regardless of age is a backlog, not a WIP list -- it
  # gets counted at the end instead of listed.
  local -a rows
  rows=( ${(f)"$(print -r -- "$index" | jq -r --arg live "${(j:,:)live}" '
    ($live | split(",")) as $sessions
    | .dirs[]
    | select(.files > 0 or .transcripts > 0)
    | select(.last_activity > (now - 86400 * 7)
             or (("notes--" + .slug) | IN($sessions[])))
    | [.slug,
       (if .topic == "" then "-" else .topic end),
       .age,
       (if .wrapped then "" else "UNWRAPPED" end)]
    | @tsv')"} )

  echo "notes"
  if (( ! ${#rows} )); then
    echo "  (nothing recent)"
  else
    local row slug
    for row in "${rows[@]}"; do
      slug="${row%%	*}"
      marker="  "
      (( ${live[(I)notes--$slug]} )) && marker="⚡"
      printf '%s\t%s\n' "$marker" "$row"
    done | column -t -s $'\t'
  fi

  local stale
  stale=$(print -r -- "$index" | jq '[.dirs[]
    | select(.wrapped == false and .last_activity <= (now - 86400 * 7))
    | select(.files > 0 or .transcripts > 0)] | length')
  (( stale > 0 )) && echo "  + ${stale} older, never distilled — notes-gc"
  echo ""

  echo "worktrees"
  local -a wt_lines
  wt_lines=()
  local -a repos
  repos=()
  [[ -n "$MONOREPO_DIR" && -d "$MONOREPO_DIR" ]] && repos+=( "${MONOREPO_DIR:A}" )
  local d
  for d in "$WORKTREES_DIR"/*(/N); do
    git -C "$d" rev-parse --git-dir &>/dev/null && wt_lines+=( "$d" )
  done
  local r
  for r in "${repos[@]}"; do
    for d in "$r"/.worktrees/*(/N); do wt_lines+=( "$d" ); done
  done

  if (( ! ${#wt_lines} )); then
    echo "  (none)"
  else
    local -a out
    out=()
    # Declared once: zsh's `local` echoes the variable when it re-declares one
    # that already exists in the same scope, which would print on every pass.
    local br note state sess repo_of
    for d in "${wt_lines[@]}"; do
      br=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
      repo_of=$(basename "$(dirname "$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)")")
      note="-"
      [[ -f "$d/.notes-link" ]] && note="${$(<"$d/.notes-link"):t}"
      state=""
      if git -C "$d" merge-base --is-ancestor HEAD origin/HEAD 2>/dev/null; then
        state="merged"
      elif [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]]; then
        state="dirty"
      fi
      sess="${repo_of}--${br//\//-}"
      sess=${sess//./-}
      marker="  "
      (( ${live[(I)$sess]} )) && marker="⚡"
      out+=( "${marker}	${repo_of}	${br}	${note}	${state}" )
    done
    printf '%s\n' "${out[@]}" | column -t -s $'\t'
  fi
  echo ""

  local -a review_dirs
  review_dirs=( "$REVIEWS_DIR"/*(/N) )
  echo "reviews: ${#review_dirs} tracked — run review-status for detail"
}

# --- Tab completion ---

_tmux_workflows_ws() { _path_files -W "$WORKSPACE" -/ }
_tmux_workflows_wt() { _path_files -W "$WORKTREES_DIR" -/ }

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
