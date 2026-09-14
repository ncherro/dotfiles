# tmux-workflows.zsh
#
# Tmux-based workflow helpers for dev environments.
# Source this file from your .zshrc:
#   source /path/to/tmux-workflows.zsh
#
# Prerequisites: tmux, git, gh (GitHub CLI), claude (for review-pr)
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

# --- Dependency check ---
for _twf_cmd in tmux git gh; do
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
    "claude --dangerously-skip-permissions '/review-pr $url'" Enter

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

# Resolve a topic query to a notes dirname. Exact matches pass through;
# fuzzy queries search existing dirs and offer fzf selection.
_notes_resolve() {
  local query="$*"
  local slug="${(L)query// /-}"

  # Exact match — use it directly
  if [[ -d "${NOTES_DIR}/${slug}" ]]; then
    echo "$slug"
    return
  fi

  # No existing dirs — create without prompting
  local -a existing=( "${NOTES_DIR}"/*(/:t) )
  if (( ${#existing} == 0 )); then
    echo "$slug"
    return
  fi

  # Score existing dirs by word overlap with the query
  local -a query_words=( ${(s:-:)slug} )
  local -a scored=()  # "score:dirname" pairs
  local d w hits best=0
  for d in "${existing[@]}"; do
    hits=0
    for w in "${query_words[@]}"; do
      [[ "$d" == *"$w"* ]] && (( hits++ ))
    done
    if (( hits > 0 )); then
      scored+=( "${hits}:${d}" )
      (( hits > best )) && best=$hits
    fi
  done

  # If only single-word matches and there are many, keep only those
  # with the longest matching word to reduce noise
  local -a candidates=()
  if (( best >= 2 )); then
    # Keep dirs with 2+ word hits
    for entry in "${scored[@]}"; do
      (( ${entry%%:*} >= 2 )) && candidates+=( "${entry#*:}" )
    done
  else
    # All matches are 1-word; include them all (fzf will rank)
    for entry in "${scored[@]}"; do
      candidates+=( "${entry#*:}" )
    done
  fi

  if (( ${#candidates} == 0 )); then
    echo "$slug"
    return
  fi

  candidates=( ${(o)candidates} )
  candidates+=( "+ create: ${slug}" )

  local pick
  pick=$( printf '%s\n' "${candidates[@]}" \
    | fzf --height=~15 --reverse --prompt="notes> " \
           --query="$slug" --select-1 --exit-0 \
           --header="Pick an existing dir or create new" )

  [[ -z "$pick" ]] && return 1

  if [[ "$pick" == "+ create: "* ]]; then
    echo "$slug"
  else
    echo "$pick"
  fi
}

# Open a notes directory in a dedicated tmux session
notes() {
  if [[ -z "$*" ]]; then
    echo "Usage: notes <topic>"
    return 1
  fi

  local dirname
  dirname=$(_notes_resolve "$@") || return 1

  local dir="${NOTES_DIR}/${dirname}"
  mkdir -p "$dir"

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

# --- Tab completion ---

_tmux_workflows_ws() { _path_files -W "$WORKSPACE" -/ }
_tmux_workflows_wt() { _path_files -W "$WORKTREES_DIR" -/ }

_tmux_workflows_init_completions() {
  compdef _tmux_workflows_ws ws
  compdef _tmux_workflows_wt wt
  compdef _tmux_workflows_ws tat
  add-zsh-hook -d precmd _tmux_workflows_init_completions
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _tmux_workflows_init_completions
