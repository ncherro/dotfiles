# tmux-workflows.zsh
#
# Tmux-based workflow helpers for dev environments.
# Source this file from your .zshrc:
#   source /path/to/tmux-workflows.zsh
#
# Prerequisites: tmux, git, gh (GitHub CLI), claude or snipe (see AGENT_CMD)
#   jq        session/review metadata
#   fzf       the notes and resume pickers
#   python3   bin/notes-index, which joins the notes dirs to the knowledge base
#
# Workflows:
#   notes <topic>        open or create an investigation, routed against the KB:
#                        _notes/<topic>/<slug>, one tmux session per topic
#   code <branch> -p …   start a coding session from one, in a linked worktree
#   review <url>         review a PR in its own tmux window
#   wip                  what am I in the middle of
#   resume               reopen the tmux sessions a reboot took out
#   recall <terms>       which dir was I working on that in
#   notes-gc             prune notes dirs that hold nothing
#   notes-settle         apply the moves /wrap recorded, once their sessions end
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

# How often `review-status --watch`, which the pr-reviews status window runs,
# asks GitHub again, in seconds.
: ${REVIEW_REFRESH_INTERVAL:=300}

# Automatic re-reviews, which every `review-status --watch` pass starts: how
# long a PR has to sit without new commits or comments for you first
# (seconds), and how many may start in one pass. REVIEW_AUTO=0 turns them off.
: ${REVIEW_AUTO:=1}
: ${REVIEW_REREVIEW_QUIET:=1200}
: ${REVIEW_REREVIEW_MAX:=2}

# Every `review-status --watch` pass also removes merged and closed reviews,
# as review-gc does. REVIEW_AUTO_GC=0 leaves them for review-gc.
: ${REVIEW_AUTO_GC:=1}

# Worktrees live inside the repo they belong to, at <repo>/.worktrees/<branch>
# (slashes in the branch flattened to dashes). Nothing to manage but the repo
# itself, and a worktree's repo is its grandparent dir rather than something
# decoded out of a mangled directory name. Add `.worktrees/` to your global
# gitignore (see gitignore_global) so the repo never reads as dirty.
: ${WORKTREES_SUBDIR:=".worktrees"}

# Coding agent that gwt, code and review launch: claude or snipe. Read at call
# time, so `export AGENT_CMD=snipe` in a shell, or `AGENT_CMD=snipe review …`
# for one run, switches without re-sourcing.
: ${AGENT_CMD:="claude"}

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

# _agent_cmd <mode> [model] — the $AGENT_CMD invocation for a permission mode
# (bypass | safer | anything else for the default), into REPLY.
_agent_cmd() {
  local mode=$1 model=$2
  REPLY=$AGENT_CMD
  case "$AGENT_CMD:$mode" in
    snipe:bypass) REPLY+=" --yolo" ;;
    *:bypass)     REPLY+=" --dangerously-skip-permissions" ;;
    *:safer)      REPLY+=" --permission-mode acceptEdits" ;;
  esac
  [[ -n "$model" ]] && REPLY+=" --model $model"
}

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
    local git_dir=$(cd -q "$(git rev-parse --git-dir)" && pwd)
    local git_common_dir=$(cd -q "$(git rev-parse --git-common-dir)" && pwd)
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
  common=$(cd -q "$dir" && cd -q "$common" && pwd) || return 1
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

  _agent_cmd "$mode" "$model"
  tmux send-keys -t "$session_name" "${REPLY} \"\$(cat ${tmpfile})\" && rm -f ${tmpfile}" Enter

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

# The GitHub host a PR URL lives on, falling back to REVIEW_GH_HOST. Reviews
# span hosts (ghe.spotify.net, spotify.ghe.com), so every gh call has to ask
# the host the PR came from rather than one global one. Into REPLY.
_review_host() {
  local url="$1"
  REPLY=""
  [[ "$url" == http*://*/* ]] && REPLY=$(echo "$url" | sed -E 's|https?://([^/]+)/.*|\1|')
  [[ -n "$REPLY" ]] || REPLY="$REVIEW_GH_HOST"
}

# The host for a review dir, from the URL in its .review-meta.json. Into REPLY.
_review_dir_host() {
  local meta="$1/.review-meta.json" url=""
  [[ -f "$meta" ]] && url=$(jq -r '.url // empty' "$meta" 2>/dev/null)
  _review_host "$url"
}

_review_infer_from_dirname() {
  local dirname="$1"
  _rv_repo=$(echo "$dirname" | sed -E 's/--[0-9]+$//')
  _rv_number=$(echo "$dirname" | grep -oE '[0-9]+$')
  _rv_owner="$REVIEW_DEFAULT_OWNER"
}

# The reviews session, with the status of every tracked review already in it
#
# `review <url>` adds a review to the session; `review` on its own gets you
# back to the session, which a reboot or a stray kill-session takes with it.
# Window 0 runs `review-status --windows --watch`, so you land on the list *and*
# on a window per review that still wants something, and their labels keep up. `resume` can recreate this session too, but deliberately starts
# everything empty -- that is the difference between the two.
_review_session() {
  local session="pr-reviews" target cmd
  local -a wins

  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$REVIEWS_DIR" -n status
    target="${session}:status"
  elif tmux list-windows -t "=$session" -F '#{window_name}' | grep -qxF status; then
    target="${session}:status"
  else
    # A session that resume recreated holds one idle shell. Make that the
    # status window rather than leaving a stray one beside it.
    wins=( ${(f)"$(tmux list-windows -t "=$session" -F '#{window_index} #{pane_current_command}')"} )
    if (( ${#wins} == 1 )) && [[ "${wins[1]#* }" == (zsh|bash|sh) ]]; then
      target="${session}:${wins[1]%% *}"
      tmux rename-window -t "$target" status
    else
      tmux new-window -t "$session" -n status -c "$REVIEWS_DIR"
      target="${session}:status"
    fi
  fi

  # automatic-rename is on globally, which would rename this back to `zsh` the
  # moment review-status finishes -- and then the check above would miss it and
  # add another window on every call.
  tmux set-window-option -t "$target" automatic-rename off >/dev/null

  # Refresh on the way in, but only into an idle shell: typing into a pane that
  # is running something is how you end up in someone else's prompt.
  cmd=$(tmux display-message -p -t "$target" '#{pane_current_command}')
  case "$cmd" in
    zsh|bash|sh) tmux send-keys -t "$target" "review-status --windows --watch" Enter ;;
  esac

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=$session"
  else
    tmux attach-session -t "=$session"
  fi
}

# Review a PR in a dedicated tmux session with Claude Code
#
# The bare name is the primary action, matching `notes`; review-status and
# review-gc are the auxiliaries. `review-pr` stays as an alias for muscle
# memory and because the Claude command is still called /review-pr.
# The pr-reviews window name for a review dir: <repo>--<author>--<number>, so
# a row of PR windows says whose PR each one is. Falls back to the dir name
# (<repo>--<number>) when the author is not recorded yet. Into REPLY.
_review_window_name() {
  local dir="$1" author=""
  local dirname="${dir:t}"
  [[ -f "$dir/.review-meta.json" ]] \
    && author=$(jq -r '.author // empty' "$dir/.review-meta.json" 2>/dev/null)
  if [[ -n "$author" ]]; then
    REPLY="${dirname%--*}--${author}--${dirname##*--}"
  else
    REPLY="$dirname"
  fi
  REPLY="${REPLY//./-}"
}

# The index of the pr-reviews window for a review dir, or empty. Found by the
# @review tag, falling back to either name for windows opened before tagging,
# so renaming them never opens a duplicate. Into REPLY.
_review_find_window() {
  local dirname="$1" name="$2"
  REPLY=$(tmux list-windows -t "=pr-reviews" \
      -F '#{window_index}'$'\t''#{@review}'$'\t''#{window_name}' 2>/dev/null \
    | awk -F'\t' -v d="$dirname" -v n="$name" \
        '$2 == d { print $1; exit } $2 == "" && ($3 == d || $3 == n) && !f { f = $1 }
         END { if (f != "") print f }' | head -1)
}

# Show a review's state on its window, for the session picker and status bar
#
# The window carries it as options: @review_state and @review_flags (the probe's
# state and flags, as last seen), and @review_icon and @review_label (what is
# drawn). @review_agent is busy or idle, set by bin/review-agent-hook from
# Claude Code's hooks. A busy agent outranks whatever GitHub says -- its
# findings are not in yet -- and an idle one on a review with nothing to show
# for it is waiting on you. busy only counts while an agent is still running in
# the window, since an agent that is killed never reports idle.
_review_apply_state() {
  local target="$1" state="$2" flags="$3"
  [[ "$flags" == "-" ]] && flags=""
  tmux set-option -w -t "$target" @review_state "$state" 2>/dev/null || return 0
  tmux set-option -w -t "$target" @review_flags "$flags"

  local agent shown="$state"
  agent=$(tmux show-options -wqv -t "$target" @review_agent)
  if [[ "$agent" == busy ]] && tmux list-panes -t "$target" -F '#{pane_current_command}' \
      | grep -qE '^([0-9]+\.[0-9]+\.[0-9]+|claude|snipe)$'; then
    shown=reviewing
  elif [[ "$agent" == idle && "$state" == open ]]; then
    shown=your-turn
  fi

  local _rv_icon _rv_label
  _review_icon_label "$shown" "$flags"
  tmux set-option -w -t "$target" @review_shown "$shown"
  tmux set-option -w -t "$target" @review_icon "$_rv_icon"
  tmux set-option -w -t "$target" @review_label "$_rv_label"
}

# What a state is drawn as, into _rv_icon and _rv_label (declare them local).
# Shared by the windows and the status cache, so a review reads the same in
# the picker whether or not it has a window.
_review_icon_label() {
  local shown="$1" flags="$2"
  case "$shown" in
    reviewing) _rv_icon="⟳" _rv_label="reviewing" ;;
    your-turn) _rv_icon="●" _rv_label="your turn" ;;
    approvable) _rv_icon="★" _rv_label="approve?" ;;
    ready)     _rv_icon="●" _rv_label="ready" ;;
    pending)   _rv_icon="✎" _rv_label="draft" ;;
    attention) _rv_icon="✉" _rv_label="${flags%%,*}"
               [[ "$flags" == *"new commits"* ]] && _rv_label+=" ↻" ;;
    updated)   _rv_icon="↻" _rv_label="updated" ;;
    commented) _rv_icon="✓" _rv_label="commented" ;;
    open)      _rv_icon="○" _rv_label="open" ;;
    approved)  _rv_icon="✔" _rv_label="approved" ;;
    merged)    _rv_icon="✔" _rv_label="merged" ;;
    closed)    _rv_icon="✗" _rv_label="closed" ;;
    *)         _rv_icon="?" _rv_label="unknown" ;;
  esac
  # Something moved under a review that is waiting on you, or that you
  # approved.
  [[ -n "$flags" && "$shown" == (approved|ready|pending|your-turn) ]] && _rv_label+=" ↻"
}

# The same, for a review dir's window in pr-reviews, if it has one.
_review_set_window_state() {
  local dirname="$1" state="$2" flags="$3"
  _review_window_name "${REVIEWS_DIR}/${dirname}"
  _review_find_window "$dirname" "$REPLY"
  [[ -n "$REPLY" ]] && _review_apply_state "=pr-reviews:${REPLY}" "$state" "$flags"
}

# A pr-reviews window for a review dir, opened in the background if it has
# none, its name brought up to date if it has. The window's index into REPLY;
# returns 1 when it was already open, 2 when it could not be opened.
_review_open_window() {
  local dirname="$1" session="pr-reviews" wname idx
  _review_window_name "${REVIEWS_DIR}/${dirname}"
  wname="$REPLY"
  _review_find_window "$dirname" "$wname"
  if [[ -n "$REPLY" ]]; then
    tmux rename-window -t "=${session}:${REPLY}" "$wname" 2>/dev/null
    tmux set-option -w -t "=${session}:${REPLY}" @review "$dirname" 2>/dev/null
    return 1
  fi
  idx=$(tmux new-window -d -P -F '#{window_index}' -t "=${session}:" \
    -n "$wname" -c "${REVIEWS_DIR}/${dirname}" 2>/dev/null) || return 2
  # Same reason as the status window: automatic-rename would rename this the
  # moment anything runs in it. The @review tag finds it again.
  tmux set-window-option -t "=${session}:${idx}" automatic-rename off >/dev/null
  tmux set-option -w -t "=${session}:${idx}" @review "$dirname" 2>/dev/null
  # Show what review-status last saw until it next looks.
  local state flags
  IFS=$'\t' read -r state _ flags _ < <(awk -F'\t' -v d="$dirname" '$2 == d' \
    "${REVIEWS_DIR}/.status.tsv" 2>/dev/null)
  [[ -n "$state" ]] && _review_apply_state "=${session}:${idx}" "$state" "$flags"
  REPLY="$idx"
}

# Every review's state as review-status last saw it, for the session picker to
# list reviews that have no window: state, dir, flags, window name, icon,
# label, url.
# Written whole and moved into place, so the picker never reads half of one.
_review_write_status_cache() {
  local cache="${REVIEWS_DIR}/.status.tsv" row state dirname flags url _rv_icon _rv_label
  {
    for row in "$@"; do
      IFS=$'\t' read -r state dirname flags _ url _ <<< "$row"
      _review_icon_label "$state" "${flags#-}"
      _review_window_name "${REVIEWS_DIR}/${dirname}"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$state" "$dirname" "$flags" "$REPLY" "$_rv_icon" "$_rv_label" "$url"
    done
  } > "${cache}.new" && mv "${cache}.new" "$cache"
}

# Point a review dir at its PR's current head and start /review-pr on it in
# the review's pr-reviews window
#
# With "background" it leaves focus where it is, so a batch of these does not
# drag you from window to window; `review` focuses the window afterwards. The
# window's target goes into REPLY. Returns 1 for a URL it cannot parse, 2 when
# there is nothing new since the last review, and 3 when the window is running
# something -- typing into that pane is how a stale agent ends up with the
# command in its prompt -- in which case the meta is left alone, so the review
# still reads as updated. A busy window's idle shell pane is used instead when
# it has one, and with "split" as the third argument a new pane is opened below
# when it does not.
#
# The automatic re-reviews pass "reuse" as the third argument and what is due
# as the fourth (commits or replies; see _review_probe). reuse types the
# command into the window's agent instead, when it has sat idle for
# REVIEW_REREVIEW_QUIET seconds -- it remembers the last review, and an agent
# idle that long is not one you are using. replies runs even with no new
# commits, as `/review-pr --replies`. Either records the run in the meta as
# auto_kind, for bin/review-agent-hook to say when it is done, and the head
# it replaces as previous_head, for /review-pr to review only what changed.
_review_launch() {
  local url="$1" background="$2" split="$3" kind="$4"
  local _rv_owner _rv_repo _rv_number
  _review_parse_url "$url"

  if [[ -z "$_rv_owner" || -z "$_rv_repo" || -z "$_rv_number" ]]; then
    echo "Could not parse owner, repo, and PR number from URL"
    return 1
  fi

  local dirname="${_rv_repo}--${_rv_number}"
  local dir="${REVIEWS_DIR}/${dirname}"
  mkdir -p "$dir"

  _review_host "$url"
  local host="$REPLY"

  # gh prints an error body (a 404, say) to stdout, so only trust the output
  # when the call succeeded.
  local head_commit="unknown" author="" pr_line
  pr_line=$(GH_HOST="$host" gh api "repos/${_rv_owner}/${_rv_repo}/pulls/${_rv_number}" \
    --jq '.head.sha + "\t" + .user.login' 2>/dev/null) || pr_line=""
  if [[ -n "$pr_line" ]]; then
    head_commit="${pr_line%%$'\t'*}"
    author="${pr_line#*$'\t'}"
  fi

  local meta="${dir}/.review-meta.json"
  if [[ -f "$meta" ]]; then
    local prev_commit
    prev_commit=$(jq -r '.head_commit' "$meta")
    [[ "$kind" != replies && "$prev_commit" == "$head_commit" && "$head_commit" != "unknown" ]] \
      && return 2
  fi

  local session="pr-reviews" target cmd pane reuse_agent=0 idle_at
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$REVIEWS_DIR"
  fi

  _review_window_name "$dir"
  _review_find_window "$dirname" "$REPLY"
  if [[ -n "$REPLY" ]]; then
    target="=${session}:${REPLY}"
    cmd=$(tmux display-message -p -t "$target" '#{pane_current_command}')
    if [[ "$split" == reuse ]]; then
      pane=$(tmux list-panes -t "$target" -F '#{pane_id} #{pane_current_command}' \
        | awk '$2 ~ /^([0-9]+\.[0-9]+\.[0-9]+|claude|snipe)$/ { print $1; exit }')
      if [[ -n "$pane" ]]; then
        # An agent busy, or idle for less than the quiet period, may be one
        # you are using: leave the window be rather than start a second. An
        # idle agent with no time went idle before bin/review-agent-hook
        # recorded one, and so has been idle at least that long.
        idle_at=$(tmux show-options -wqv -t "$target" @review_agent_idle_at)
        if [[ "$(tmux show-options -wqv -t "$target" @review_agent)" != idle ]] \
            || (( EPOCHSECONDS - ${idle_at:-0} < REVIEW_REREVIEW_QUIET )); then
          REPLY="$target"
          return 3
        fi
        reuse_agent=1
      fi
    fi
    if (( ! reuse_agent )) && [[ "$cmd" != (zsh|bash|sh) ]]; then
      # Any idle shell pane in the window will do, e.g. one an earlier split
      # left behind.
      pane=$(tmux list-panes -t "$target" -F '#{pane_id} #{pane_current_command}' \
        | awk '$2 ~ /^(zsh|bash|sh)$/ { print $1; exit }')
      if [[ -z "$pane" && "$split" == split ]]; then
        pane=$(tmux split-window -v -d -P -F '#{pane_id}' -t "$target" -c "$dir")
      fi
      if [[ -z "$pane" ]]; then
        REPLY="$target"
        return 3
      fi
    fi
  fi

  if [[ -f "$meta" ]]; then
    local tmp
    tmp=$(jq \
      --arg head "$head_commit" \
      --arg author "$author" \
      --arg reviewed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg kind "$kind" \
      --argjson now "$EPOCHSECONDS" \
      '(if .head_commit != $head then .previous_head = .head_commit else . end)
       | .head_commit = $head | .reviewed_at = $reviewed
       | del(.ready_at, .ready_findings, .ready_replies, .verdict, .verdict_head)
       | if $kind != "" then .auto_kind = $kind | .auto_started_at = $now
         else del(.auto_kind, .auto_started_at) end
       | if $author != "" then .author = $author else . end' "$meta")
    printf '%s\n' "$tmp" > "$meta"
  else
    jq -n \
      --arg url "$url" \
      --arg owner "$_rv_owner" \
      --arg repo "$_rv_repo" \
      --argjson number "$_rv_number" \
      --arg author "$author" \
      --arg head "$head_commit" \
      --arg reviewed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{url: $url, owner: $owner, repo: $repo, pr_number: $number,
        author: $author, head_commit: $head, reviewed_at: $reviewed}' > "$meta"
  fi

  # Named after the meta write, which may have just recorded the author.
  _review_window_name "$dir"
  local window="$REPLY"
  if [[ -n "$target" ]]; then
    # An older window keeps its place but takes the new name.
    tmux rename-window -t "$target" "$window" 2>/dev/null
  else
    target="=${session}:$(tmux new-window -d -P -F '#{window_index}' \
      -t "=${session}:" -n "$window" -c "$dir")"
  fi
  # automatic-rename is on globally and would rename this to `claude` and then
  # `zsh`. The @review tag is what finds the window again; the name is for you.
  tmux set-window-option -t "$target" automatic-rename off >/dev/null
  tmux set-option -w -t "$target" @review "$dirname" 2>/dev/null

  local slash="/review-pr $url"
  [[ "$kind" == replies ]] && slash="/review-pr --replies $url"
  if (( reuse_agent )); then
    # Text and Enter apart: sent together, the agent's prompt can take the
    # Enter as part of a paste and add a newline instead of submitting.
    tmux send-keys -t "$pane" -l "$slash"
    sleep 0.3
    tmux send-keys -t "$pane" Enter
  else
    _agent_cmd bypass
    tmux send-keys -t "${pane:-$target}" "${REPLY} '$slash'" Enter
  fi
  REPLY="$target"
}

review() {
  local url="$1"
  if [[ -z "$url" ]]; then
    _review_session
    return
  fi

  _review_launch "$url"
  local rc=$? target="$REPLY"
  case $rc in
    1) return 1 ;;
    2) echo "No new commits since last review"; return 0 ;;
    3) echo "That review's window is running something -- run /review-pr there, or exit it and re-run review" ;;
  esac

  tmux select-window -t "$target"
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=pr-reviews"
  else
    tmux attach-session -t "=pr-reviews"
  fi
}

alias review-pr=review

# One review's state, as a single TSV line: state, dir, flags, title, url, due
#
# No field is ever empty -- "-" stands in for one -- because read(1) with
# IFS=tab treats a run of tabs as a single delimiter, which silently shifts
# every later field left.
#
# state is attention | pending | approvable | ready | updated | commented |
# open | approved | merged | closed | unknown. pending: your review is drafted
# on the PR but not submitted. approvable: /review-pr's verdict was approve, at
# the PR's current head. ready: /review-pr has findings you have not posted
# yet.
#
# due is what an automatic re-review would do now -- commits (a review of what
# changed) or replies (answer the threads) -- or "-" for nothing. It waits for
# REVIEW_REREVIEW_QUIET seconds without new activity, timed from when a probe
# first saw it, which keeps working through rebases that make GitHub's commit
# dates meaningless. Never due on your own PR, nor while findings or a draft
# review wait for you: re-reviewing would replace findings you have not read,
# and GitHub allows one pending review at a time.
#
# Split out of review-status so the calls can be fanned out, and so the session
# builder can act on exactly the data the report renders rather than scraping
# it back out of formatted text.
_review_probe() {
  local dir="$1" my_login="$2"
  local dirname="${dir:t}"
  local meta="${dir}/.review-meta.json"
  _review_dir_host "$dir"
  local host="$REPLY"

  local owner repo number head_commit="unknown" url=""
  if [[ -f "$meta" ]]; then
    owner=$(jq -r '.owner' "$meta")
    repo=$(jq -r '.repo' "$meta")
    number=$(jq -r '.pr_number' "$meta")
    head_commit=$(jq -r '.head_commit' "$meta")
    url=$(jq -r '.url' "$meta")
  else
    repo=${dirname%--[0-9]#}
    number=${dirname##*--}
    owner="$REVIEW_DEFAULT_OWNER"
    url="https://${REVIEW_GH_HOST}/${owner}/${repo}/pull/${number}"
  fi

  local pr_json
  pr_json=$(GH_HOST="$host" gh api "repos/${owner}/${repo}/pulls/${number}" \
    --jq '{state: .state, merged: .merged, head: .head.sha, title: .title,
           author: .user.login}' 2>/dev/null) || pr_json=""

  if [[ -z "$pr_json" ]]; then
    printf 'unknown\t%s\t-\tcould not fetch PR status\t%s\t-\n' "$dirname" "$url"
    return
  fi

  # Reviews opened before the author was recorded get it now, so their
  # windows can be named for it.
  if [[ -f "$meta" ]] && ! jq -e '.author // empty' "$meta" &>/dev/null; then
    local _author _tmp
    _author=$(print -r -- "$pr_json" | jq -r '.author // empty')
    [[ -n "$_author" ]] && _tmp=$(jq --arg a "$_author" '.author = $a' "$meta") \
      && printf '%s\n' "$_tmp" > "$meta"
  fi

  local state is_merged current_head title
  state=$(print -r -- "$pr_json" | jq -r '.state')
  is_merged=$(print -r -- "$pr_json" | jq -r '.merged')
  current_head=$(print -r -- "$pr_json" | jq -r '.head')
  title=$(print -r -- "$pr_json" | jq -r '.title')
  local short_title="${title:0:60}"
  (( ${#title} > 60 )) && short_title="${short_title}…"

  if [[ "$is_merged" == "true" ]]; then
    printf 'merged\t%s\t-\t%s\t%s\t-\n' "$dirname" "$short_title" "$url"
    return
  fi
  if [[ "$state" == "closed" ]]; then
    printf 'closed\t%s\t-\t%s\t%s\t-\n' "$dirname" "$short_title" "$url"
    return
  fi

  # Your reviews, as: pending draft (0/1), latest submitted state, when it was
  # submitted. A pending review is only ever visible to its author, so it is
  # always yours.
  local my_reviews="" has_pending=0 my_review_state="" my_submitted_at=""
  if [[ -n "$my_login" ]]; then
    my_reviews=$(GH_HOST="$host" gh api "repos/${owner}/${repo}/pulls/${number}/reviews?per_page=100" \
      --jq "[.[] | select(.user.login == \"${my_login}\")]
            | [(map(select(.state == \"PENDING\")) | length > 0 | if . then 1 else 0 end),
               (map(select(.state != \"PENDING\")) | last | .state // \"-\"),
               (map(select(.state != \"PENDING\")) | last | .submitted_at // \"-\")]
            | @tsv" 2>/dev/null) || my_reviews=""
  fi
  if [[ -n "$my_reviews" ]]; then
    IFS=$'\t' read -r has_pending my_review_state my_submitted_at <<< "$my_reviews"
    [[ "$my_review_state" == "-" ]] && my_review_state=""
    [[ "$my_submitted_at" == "-" ]] && my_submitted_at=""
  fi

  # From the meta: when /review-pr last ran here, the activity last seen and
  # when it was first seen, and ready_at -- set by /review-pr once its findings
  # are ready, cleared by the next launch.
  local reviewed_at="" ready_at="" seen_activity="" seen_at=0 verdict="" verdict_head=""
  if [[ -f "$meta" ]]; then
    IFS=$'\t' read -r reviewed_at ready_at seen_activity seen_at verdict verdict_head < <(jq -r \
      '[.reviewed_at // "-", .ready_at // "-", .activity // "-", .activity_seen_at // 0,
        .verdict // "-", .verdict_head // "-"]
       | @tsv' "$meta")
    [[ "$reviewed_at" == "-" ]] && reviewed_at=""
    [[ "$ready_at" == "-" ]] && ready_at=""
  fi

  local has_new_commits=0
  [[ "$head_commit" != "unknown" && "$head_commit" != "$current_head" ]] && has_new_commits=1

  # Replies to you, in the threads you are part of. GitHub points every reply
  # at the thread's first comment, so that comment's id names the thread. As:
  # replies newer than your last comment in their thread (unanswered), those
  # that are also newer than the last /review-pr run (new), and when the
  # latest reply in any of your threads was made.
  local reply_count=0 new_replies=0 latest_reply="-"
  if [[ -n "$my_login" ]]; then
    local all_comments
    all_comments=$(GH_HOST="$host" gh api "repos/${owner}/${repo}/pulls/${number}/comments" \
      --paginate --jq '.[] | {id, in_reply_to_id, created_at, user: .user.login}' 2>/dev/null) \
      || all_comments=""
    if [[ -n "$all_comments" ]]; then
      IFS=$'\t' read -r reply_count new_replies latest_reply < <(print -r -- "$all_comments" \
        | jq -rs --arg me "$my_login" --arg since "$reviewed_at" '
        map(. + {thread: ((.in_reply_to_id // .id) | tostring)}) as $all
        | ($all | map(select(.user == $me)) | group_by(.thread)
           | map({key: .[0].thread, value: (map(.created_at) | max)}) | from_entries) as $mine
        | [$all[] | select(.user != $me and $mine[.thread] != null)] as $theirs
        | ($theirs | map(select(.created_at > $mine[.thread]))) as $unanswered
        | [($unanswered | length),
           ($unanswered | map(select(.created_at > $since)) | length),
           ($theirs | map(.created_at) | max // "-")] | @tsv')
    fi
  fi

  # Top-level comments for you, from people rather than bots: ones that
  # mention you, and once you have reviewed, anything after your review. The
  # same three counts, with unanswered meaning newer than your last review or
  # top-level comment.
  local comment_count=0 new_comments=0 latest_comment="-"
  if [[ -n "$my_login" ]]; then
    local issue_comments
    issue_comments=$(GH_HOST="$host" gh api "repos/${owner}/${repo}/issues/${number}/comments" \
      --paginate --jq '.[] | {created_at, body, user: .user.login, bot: (.user.type == "Bot")}' \
      2>/dev/null) || issue_comments=""
    if [[ -n "$issue_comments" ]]; then
      IFS=$'\t' read -r comment_count new_comments latest_comment < <(print -r -- "$issue_comments" \
        | jq -rs --arg me "$my_login" --arg since "$reviewed_at" --arg reviewed "$my_submitted_at" '
        ([(map(select(.user == $me)) | map(.created_at) | max // ""), $reviewed] | max) as $my_last
        | map(select(.user != $me and (.bot | not)
                     and ((.body | contains("@" + $me))
                          or ($reviewed != "" and .created_at > $reviewed)))) as $for_me
        | ($for_me | map(select(.created_at > $my_last))) as $unanswered
        | [($unanswered | length),
           ($unanswered | map(select(.created_at > $since)) | length),
           ($for_me | map(.created_at) | max // "-")] | @tsv')
    fi
  fi

  # Activity is your PR's head plus the latest comment for you. A change
  # restarts the quiet period; nothing you do yourself changes it.
  local activity="${current_head}|${latest_reply}|${latest_comment}" quiet=0
  if [[ -f "$meta" && "$activity" != "$seen_activity" ]]; then
    local _tmp
    seen_at=$EPOCHSECONDS
    _tmp=$(jq --arg a "$activity" --argjson t "$seen_at" \
      '.activity = $a | .activity_seen_at = $t' "$meta") && printf '%s\n' "$_tmp" > "$meta"
  fi
  (( quiet = EPOCHSECONDS - seen_at ))

  local is_ready=0 has_activity=0
  [[ -n "$ready_at" && ( -z "$my_submitted_at" || "$my_submitted_at" < "$ready_at" ) ]] && is_ready=1
  (( has_new_commits || new_replies || new_comments )) && has_activity=1

  local out_state flags=""
  local -a parts=()
  if [[ "$my_review_state" == "APPROVED" ]]; then
    out_state=approved
    (( has_new_commits )) && flags="new commits"
  elif (( reply_count > 0 || comment_count > 0 )); then
    out_state=attention
    (( reply_count > 0 )) && parts+=("${reply_count} replies")
    (( comment_count > 0 )) && parts+=("${comment_count} comments")
    (( has_new_commits )) && parts+=("new commits")
    flags="${(j:, :)parts}"
  elif (( has_pending )); then
    out_state=pending
    (( has_activity )) && flags="new activity"
  elif [[ "$verdict" == approve* && "$verdict_head" == "$current_head" ]]; then
    # A new commit makes the verdict stale, and the PR reads as updated.
    out_state=approvable
    [[ "$verdict" == approve-with-suggestions ]] && flags="suggestions"
  elif (( is_ready )); then
    out_state=ready
    (( has_activity )) && flags="new activity"
  elif (( has_new_commits )); then
    out_state=updated
  elif [[ -n "$my_review_state" ]]; then
    out_state=commented
  else
    out_state=open
  fi

  local due="-" author
  author=$(print -r -- "$pr_json" | jq -r '.author // empty')
  if [[ -n "$my_login" && "$author" != "$my_login" ]] && (( quiet >= REVIEW_REREVIEW_QUIET )) \
      && (( ! has_pending && ! is_ready )) && [[ "$out_state" != approvable ]]; then
    if (( has_new_commits )); then
      due=commits
    elif [[ "$out_state" != approved ]] && (( new_replies || new_comments )); then
      due=replies
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$out_state" "$dirname" "${flags:--}" "$short_title" "$url" "$due"
}

# Every review's state, probed in parallel.
#
# Serially this was ~40s for eleven reviews: two or three GitHub round trips
# each, one after another. The work is all waiting, so it fans out -- six at a
# time, which is enough to hide the latency without opening a connection per
# review.
_review_probe_all() {
  local -a dirs=( "${REVIEWS_DIR}"/*(/N) )
  (( ${#dirs} )) || return 0

  # Your login can differ per host, so look it up once for each host in use.
  local -A logins
  local d h
  for d in "${dirs[@]}"; do
    _review_dir_host "$d"
    h="$REPLY"
    (( ${+logins[$h]} )) && continue
    logins[$h]=$(GH_HOST="$h" gh api user --jq '.login' 2>/dev/null) || logins[$h]=""
  done

  local tmp
  tmp=$(mktemp -d) || return 1
  local -i i=0
  for d in "${dirs[@]}"; do
    (( i++ ))
    _review_dir_host "$d"
    _review_probe "$d" "${logins[$REPLY]}" > "${tmp}/$(printf '%03d' $i)" &
    (( i % 6 )) || wait
  done
  wait
  cat "${tmp}"/*(N)
  rm -rf "$tmp"
}

# Show status of all tracked PR reviews
#
#   review-status              the report
#   review-status --windows    + a tmux window per review still wanting work
#   review-status --rereview   + /review-pr again on every PR with new commits
#   review-status --auto       + the automatic re-reviews that are due, and
#                              merged and closed reviews removed
#   review-status --watch      all of that, then again every
#                              REVIEW_REFRESH_INTERVAL seconds until ctrl-c
#
# --watch is what keeps the window labels current between agent runs: replies
# and new commits only show up when something asks GitHub. --windows and
# --rereview act on the first pass only -- afterwards they would reopen windows
# you closed, and re-review on a timer. --auto is on for every pass, unless
# REVIEW_AUTO=0: it is the timer, but one that waits for a PR to go quiet,
# and never touches an agent you are using (see _review_launch).
review-status() {
  setopt local_options typeset_silent no_xtrace no_verbose
  local open_windows=0 rereview=0 watch=0 auto=0 arg
  for arg in "$@"; do
    case "$arg" in
      --windows)  open_windows=1 ;;
      --rereview) rereview=1 ;;
      --auto)     auto=1 ;;
      --watch)    watch=1 ;;
      *) echo "usage: review-status [--windows] [--rereview] [--auto] [--watch]" >&2; return 1 ;;
    esac
  done

  if (( watch )); then
    local -a once=( "${(@)argv:#--watch}" )
    while true; do
      clear
      review-status "${once[@]}" --auto
      once=()
      print -P "\n%F{8}Refreshed $(date +%H:%M), again every $(( REVIEW_REFRESH_INTERVAL / 60 ))m. ctrl-c to stop.%f"
      sleep "$REVIEW_REFRESH_INTERVAL"
    done
  fi

  local reviews_dir="${REVIEWS_DIR}"
  if [[ ! -d "$reviews_dir" ]]; then
    echo "No reviews directory found"
    return 1
  fi
  local -a review_dirs=( "$reviews_dir"/*(/N) )
  if (( ${#review_dirs} == 0 )); then
    echo "No reviews found"
    return 0
  fi

  _review_spinner() {
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while true; do
      printf '\r  %s %s' "${chars:$((i % ${#chars})):1}" "$1" >&2
      ((i++))
      sleep 0.08
    done
  }
  _review_spinner "Checking ${#review_dirs} reviews..." &!
  local spin_pid=$!
  trap "kill $spin_pid 2>/dev/null; printf '\r\033[K' >&2" EXIT INT TERM

  local -a rows
  rows=( ${(f)"$(_review_probe_all)"} )

  kill $spin_pid 2>/dev/null
  wait $spin_pid 2>/dev/null
  printf '\r\033[K' >&2
  trap - EXIT INT TERM

  if (( ! ${#rows} )); then
    echo "No reviews found"
    return 0
  fi

  local -a attention pending approvable ready updated commented open approved merged closed unknown
  local -a actionable stale
  local row state dirname flags title url

  # Each row is labelled <repo>--<author>--<number>, or the dir name when the
  # author is not recorded. The column is as wide as the longest label.
  local -A labels
  local author
  local -i w=28
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r state dirname _ <<< "$row"
    author=$(jq -r '.author // empty' "${reviews_dir}/${dirname}/.review-meta.json" 2>/dev/null)
    if [[ -n "$author" ]]; then
      labels[$dirname]="${dirname%--*}--${author}--${dirname##*--}"
    else
      labels[$dirname]="$dirname"
    fi
    (( ${#labels[$dirname]} > w )) && w=${#labels[$dirname]}
  done

  # Merged and closed reviews go, as review-gc would, so the list stays the
  # work. One whose agent you may be using is left for a later pass.
  local -a cleaned kept
  if (( auto && REVIEW_AUTO_GC )); then
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r state dirname _ <<< "$row"
      if [[ "$state" == (merged|closed) ]] && ! _review_agent_in_use "$dirname"; then
        _review_remove "$dirname"
        cleaned+=( "  ${labels[$dirname]} (${state})" )
      else
        kept+=( "$row" )
      fi
    done
    rows=( "${kept[@]}" )
  fi

  local label
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r state dirname flags title url due <<< "$row"
    [[ "$flags" == "-" ]] && flags=""
    label="${labels[$dirname]}"
    case "$state" in
      attention)
        attention+=( "  * $(printf '%-*s %-20s %s' $w "$label" "[$flags]" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" )
        [[ "$flags" == *"new commits"* ]] && stale+=( "$url" ) ;;
      pending)
        pending+=( "  > $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" ) ;;
      approvable)
        approvable+=( "  ★ $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" ) ;;
      ready)
        ready+=( "  > $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" ) ;;
      updated)
        updated+=( "  ~ $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" )
        stale+=( "$url" ) ;;
      commented)
        commented+=( "    $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" ) ;;
      open)
        open+=( "    $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" )
        actionable+=( "$dirname" ) ;;
      approved) approved+=( "  ${flags:+~} $(printf '%-*s %s' $w "$label" "$title")" "    ${url}" "" ) ;;
      merged)   merged+=( "  $(printf '%-*s %s' $(( w + 2 )) "$label" "$title")" "    ${url}" "" ) ;;
      closed)   closed+=( "  $(printf '%-*s %s' $(( w + 2 )) "$label" "$title")" "    ${url}" "" ) ;;
      *)        unknown+=( "  ? ${label}  (${title})" ) ;;
    esac
  done

  local -a group_names group_vars
  (( ${#attention} )) && { echo "Needs attention:"; printf '%s\n' "${attention[@]}"; echo "" }
  (( ${#approvable} )) && { echo "Ready to approve:"; printf '%s\n' "${approvable[@]}"; echo "" }
  (( ${#ready}     )) && { echo "Ready to post:";  printf '%s\n' "${ready[@]}";     echo "" }
  (( ${#pending}   )) && { echo "Pending review:"; printf '%s\n' "${pending[@]}";   echo "" }
  (( ${#updated}   )) && { echo "Updated:";        printf '%s\n' "${updated[@]}";   echo "" }
  (( ${#open}      )) && { echo "Open:";           printf '%s\n' "${open[@]}";      echo "" }
  (( ${#commented} )) && { echo "Commented:";      printf '%s\n' "${commented[@]}"; echo "" }
  (( ${#approved}  )) && { echo "Approved:";       printf '%s\n' "${approved[@]}";  echo "" }
  (( ${#merged}    )) && { echo "Merged:";         printf '%s\n' "${merged[@]}";    echo "" }
  (( ${#closed}    )) && { echo "Closed:";         printf '%s\n' "${closed[@]}" }
  (( ${#unknown}   )) && { echo "Unknown:";        printf '%s\n' "${unknown[@]}" }
  (( ${#cleaned}   )) && { echo "Cleaned up:";     printf '%s\n' "${cleaned[@]}" }

  # A window each for the reviews still wanting something, so the session you
  # come back to is the work rather than a list of it. Commented, approved,
  # merged and closed get nothing -- there is no work left in them.
  if (( open_windows )); then
    if [[ -z "$TMUX" ]]; then
      echo ""
      echo "review-status: --windows needs to run inside tmux"
      return 0
    fi
    local opened=0
    for dirname in "${actionable[@]}"; do
      _review_open_window "$dirname" && (( opened++ ))
    done
    echo ""
    echo "${opened} window(s) opened, ${#actionable} review(s) still wanting work"
  fi

  _review_write_status_cache "${rows[@]}"

  # Every open review window shows what was just found, whether or not
  # --windows opened it.
  if tmux has-session -t "=pr-reviews" 2>/dev/null; then
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r state dirname flags _ <<< "$row"
      _review_set_window_state "$dirname" "$state" "$flags"
    done
  fi

  # Re-review whatever has moved since the last review: updated, and needs
  # attention with new commits. Launched in the background, so nothing steals
  # focus; a window already running something gets a new pane below rather
  # than being typed into.
  # Re-review what has gone quiet since it last moved, a few per pass.
  if (( auto && REVIEW_AUTO )) && [[ -n "$TMUX" ]]; then
    local auto_started=0 due
    local -a auto_lines=()
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r state dirname _ _ url due <<< "$row"
      [[ "$due" == (commits|replies) ]] || continue
      if (( auto_started >= REVIEW_REREVIEW_MAX )); then
        auto_lines+=( "  next pass: ${labels[$dirname]}" )
        continue
      fi
      _review_launch "$url" background reuse "$due"
      case $? in
        0) auto_lines+=( "  re-reviewing ${labels[$dirname]} (${due})" ); (( auto_started++ )) ;;
        3) auto_lines+=( "  waiting on ${labels[$dirname]} -- its window is in use" ) ;;
      esac
    done
    if (( ${#auto_lines} )); then
      echo ""
      echo "Automatic re-reviews:"
      printf '%s\n' "${auto_lines[@]}"
    fi
  fi

  if (( rereview )); then
    echo ""
    if (( ! ${#stale} )); then
      echo "Nothing to re-review"
      return 0
    fi
    local started=0 rc
    for url in "${stale[@]}"; do
      _review_launch "$url" background split
      rc=$?
      case $rc in
        0) echo "  re-reviewing ${url}"; (( started++ )) ;;
        3) echo "  skipped ${url} -- its window is running something" ;;
        *) echo "  could not re-review ${url}" ;;
      esac
    done
    echo "${started} of ${#stale} re-review(s) started in pr-reviews"
  fi
}


# Remove review dirs for merged/closed PRs
review-gc() {
  setopt local_options typeset_silent no_xtrace no_verbose
  local reviews_dir="${REVIEWS_DIR}"
  local -a to_remove

  # Same probe review-status uses, so the two always agree on what is merged.
  local row state dirname
  for row in ${(f)"$(_review_probe_all)"}; do
    IFS=$'\t' read -r state dirname _ <<< "$row"
    [[ "$state" == (merged|closed) ]] && to_remove+=("$dirname")
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
    _review_remove "$dirname"
    echo "  removed ${dirname}"
  done
}

# Remove a review dir and its pr-reviews window
_review_remove() {
  local dirname="$1"
  _review_window_name "${REVIEWS_DIR}/${dirname}"
  _review_find_window "$dirname" "$REPLY"
  [[ -n "$REPLY" ]] && tmux kill-window -t "=pr-reviews:${REPLY}" 2>/dev/null
  rm -rf "${REVIEWS_DIR}/${dirname}"
}

# Whether a review's window has an agent you may be using: busy, or idle for
# less than REVIEW_REREVIEW_QUIET seconds -- the same test the automatic
# re-reviews use before typing into one (see _review_launch).
_review_agent_in_use() {
  local dirname="$1" target pane idle_at
  _review_window_name "${REVIEWS_DIR}/${dirname}"
  _review_find_window "$dirname" "$REPLY"
  [[ -n "$REPLY" ]] || return 1
  target="=pr-reviews:${REPLY}"
  pane=$(tmux list-panes -t "$target" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
    | awk '$2 ~ /^([0-9]+\.[0-9]+\.[0-9]+|claude|snipe)$/ { print $1; exit }')
  [[ -n "$pane" ]] || return 1
  idle_at=$(tmux show-options -wqv -t "$target" @review_agent_idle_at)
  [[ "$(tmux show-options -wqv -t "$target" @review_agent)" != idle ]] \
    || (( EPOCHSECONDS - ${idle_at:-0} < REVIEW_REREVIEW_QUIET ))
}

# --- Workflow: Notes ---
#
# A notes dir carries `.session.json`, mirroring the `.review-meta.json` that
# review already writes. It is the join key between a scratch dir, the
# worktrees that investigation spawned, and the knowledge base topic it
# distills into. `notes-index` reads it; `code` and `/wrap` write to it.
#
# Layout is two levels: _notes/<topic>/<slug>/, where <topic> is a knowledge
# base topic slug and <slug> one investigation. An investigation with no topic
# yet goes in _notes/inbox/<slug>/ until /wrap routes it. Dirs are addressed by
# that path under NOTES_DIR ("rel"): `<topic>/<slug>`, `<topic>` for a topic
# dir's root, or a bare `<slug>` for a dir that predates the layout.
#
# tmux follows the layout: one session per topic dir (notes--<topic>), one
# window per investigation in it.

: ${NOTES_INBOX:=inbox}

# Normalize a free-text query into a directory name.
_notes_slug() {
  local s="${(L)*}"
  s="${s//[^a-z0-9._-]/-}"
  # Collapse separator runs and trim the ends: "admin api / user status"
  # should slug to admin-api-user-status, not admin-api--user-status.
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

# Whether a top-level dir is a topic dir (as opposed to a lone investigation
# from before the layout): a knowledge base topic, the inbox, or a dir that
# notes or notes-merge marked as one.
_notes_is_topic_dir() {
  local top="$1"
  [[ "$top" == "$NOTES_INBOX" || -f "$NOTES_KB/topics/${top}.md" ]] && return 0
  [[ -f "${NOTES_DIR}/${top}/.session.json" ]] && command -v jq &>/dev/null \
    && jq -e --arg t "$top" '.kind == "topic" or ((.absorbed // []) != [] and .topic == $t)' \
         "${NOTES_DIR}/${top}/.session.json" &>/dev/null
}

# Whether <topic>/<sub> is an investigation rather than a dir that belongs to
# the topic root (scripts/, docs/): it has its own metadata, or notes-merge
# recorded it as one.
_notes_is_investigation() {
  local top="$1" sub="$2"
  [[ -f "${NOTES_DIR}/${top}/${sub}/.session.json" ]] && return 0
  [[ -f "${NOTES_DIR}/${top}/.session.json" ]] && command -v jq &>/dev/null \
    && jq -e --arg s "$sub" '(.absorbed // []) | any((.subdir // .slug) == $s)' \
         "${NOTES_DIR}/${top}/.session.json" &>/dev/null
}

# Mark a topic dir's root, so notes-index lays it out as one even before the
# knowledge base has a topic file for it.
_notes_topic_init() {
  local top="$1"
  local meta="${NOTES_DIR}/${top}/.session.json"
  [[ -f "$meta" ]] && return 0
  command -v jq &>/dev/null || return 0
  local topic="$top"
  [[ "$top" == "$NOTES_INBOX" ]] && topic=""
  jq -n \
    --arg slug "$top" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg topic "$topic" \
    '{slug: $slug, kind: "topic", created: $created, topic: $topic,
      question: "", worktrees: [], wrapped_at: null, absorbed: []}' > "$meta"
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
           "$NOTES_DIR"/*(/N) "$NOTES_DIR"/*/.session.json(N) \
           "$NOTES_DIR"/*/*/.session.json(N); do
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
#   <rel>           an existing dir: <topic>/<slug>, <topic>, or <slug>
#   +topic:<slug>   a new investigation in that knowledge base topic
#   +create:<slug>  a new investigation in the inbox
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
  # ...including a path (`notes distribution-api/versioning`), and an
  # investigation's own name when only one topic has one by that name.
  if [[ "$query" == */* && -d "${NOTES_DIR}/${query%/}" ]]; then
    print -r -- "${query%/}"
    return
  fi
  local -a named
  named=( "$NOTES_DIR"/*/"$slug"(/N) )
  if (( ${#named} == 1 )) && _notes_is_investigation "${named[1]:h:t}" "$slug"; then
    print -r -- "${named[1]:h:t}/${slug}"
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

  # --ignore-case: fzf's smart case would make `notes MC-1234 ...` match
  # nothing (slugs are lowercase), and --exit-0 then returns silently.
  local pick
  pick=$(
    {
      cat "$NOTES_CACHE"
      printf '+ %-30s %-26s %5s  %-9s %s\t%s\n' \
        "new in ${NOTES_INBOX}" "$slug" "" "[new]" \
        "no knowledge base topic yet — /wrap will route it later" \
        "+create:${slug}"
    } | fzf --height=~20 --reverse --ignore-case \
            --delimiter=$'\t' --with-nth=1 \
            --query="$query" --select-1 --exit-0 \
            --prompt='notes> ' \
            --header='enter: open · a [topic] row starts a new investigation in that topic' \
            --preview="'$NOTES_BIN/notes-preview' {2}" \
            --preview-window='right,52%,wrap,border-left'
  ) || return 1

  [[ -n "$pick" ]] || return 1
  print -r -- "${pick##*$'\t'}"
}

# Open the tmux window for a notes dir, creating session and window as
# needed, and switch to it.
#
#   <topic>/<slug>  ->  session notes--<topic>, a window for <slug>
#   <topic>         ->  session notes--<topic>, a window at the topic root
#   <slug>          ->  session notes--<slug>  (a dir from before the layout)
#
# Windows are found by a @notes tag holding the rel path, falling back to the
# pane's cwd for sessions opened before windows were tagged. Not by name:
# automatic-rename is on, and tmux reads a dot in a `-t` target as a pane
# separator.
_notes_open() {
  _notes_ensure_window "$1" || return 1
  local session="${REPLY%%:*}"
  tmux select-window -t "=${REPLY}"

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=${session}"
  else
    tmux attach-session -t "=${session}"
  fi
}

# Create (or find) the session and window for a notes dir without switching
# to it, setting REPLY to `<session>:<window index>`. Shared by notes(1) and
# resume(1), so a reopened investigation is the same window either way.
_notes_ensure_window() {
  local rel="$1"
  local dir="${NOTES_DIR}/${rel}"
  local top="${rel%%/*}" win="${rel##*/}"
  local session="notes--${top}"
  local idx=""

  if ! tmux has-session -t "=${session}" 2>/dev/null; then
    idx=$(tmux new-session -d -P -F '#{window_index}' \
      -s "$session" -n "$win" -c "$dir") || return 1
  else
    idx=$(tmux list-windows -t "=${session}" \
        -F '#{window_index}'$'\t''#{@notes}'$'\t''#{pane_current_path}' \
      | awk -F'\t' -v r="$rel" -v d="${dir:A}" \
          '$2 == r { print $1; exit } $2 == "" && $3 == d && !f { f = $1 }
           END { if (f != "") print f }' | head -1)
    if [[ -z "$idx" ]]; then
      idx=$(tmux new-window -d -P -F '#{window_index}' \
        -t "=${session}:" -n "$win" -c "$dir") || return 1
    fi
  fi
  tmux set-option -w -t "=${session}:${idx}" @notes "$rel" 2>/dev/null
  REPLY="${session}:${idx}"
}

# Open an investigation in its topic's tmux session
#
# Usage:
#   notes <query>                       resolve against the KB, open or create
#   notes <topic>/<slug>                open that investigation directly
#   notes <query> -q "<question>"       record what the session is actually asking
#   notes <query> -t <kb-topic>         start it in that topic, skipping the picker
#
# New investigations land in _notes/<topic>/<slug>/, or _notes/inbox/<slug>/
# when no topic fits yet.
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
      *)
        positional+=("$1"); shift ;;
    esac
  done
  set -- "${positional[@]}"

  if [[ -z "$*" ]]; then
    echo "Usage: notes <query> [-q \"<question>\"] [-t <kb-topic>]"
    return 1
  fi

  # Finish any moves /wrap left pending, so the picker shows where things are.
  notes-settle -q

  local slug rel resolved
  slug=$(_notes_slug "$@")
  [[ -n "$slug" ]] || return 1

  if [[ -n "$topic" ]]; then
    # An explicit topic is the answer: no picker. An existing top-level dir of
    # that name is still reused, and just gets tagged.
    if [[ "$slug" == "$topic" ]]; then
      rel="$topic"
    elif [[ -d "${NOTES_DIR}/${slug}" ]] && ! _notes_is_topic_dir "$slug"; then
      rel="$slug"
    else
      rel="${topic}/${slug}"
    fi
  else
    resolved=$(_notes_resolve "$@") || return 1
    case "$resolved" in
      +topic:*)
        topic="${resolved#+topic:}"
        if [[ "$slug" == "$topic" ]]; then
          rel="$topic"
        else
          rel="${topic}/${slug}"
        fi ;;
      +create:*)
        rel="${NOTES_INBOX}/${resolved#+create:}" ;;
      *)
        rel="$resolved" ;;
    esac
  fi
  [[ -n "$rel" ]] || return 1

  local dir="${NOTES_DIR}/${rel}"
  mkdir -p "$dir" || return 1

  if [[ "$rel" == */* ]]; then
    _notes_topic_init "${rel%%/*}"
    # The topic dir it lives in is its topic; inbox means none yet.
    [[ -z "$topic" && "${rel%%/*}" != "$NOTES_INBOX" ]] && topic="${rel%%/*}"
    _notes_session_init "$dir" "$rel" "$topic" "$question"
  elif _notes_is_topic_dir "$rel"; then
    _notes_topic_init "$rel"
  else
    _notes_session_init "$dir" "$rel" "$topic" "$question"
  fi
  # -q/-t given for a dir that already exists should update it, not be dropped.
  [[ -n "$question" ]] && _notes_session_set "$dir" question "$question"
  [[ -n "$topic" && "$rel" != "$topic" ]] && _notes_session_set "$dir" topic "$topic"

  _notes_open "$rel"
}

# Rebuild the routing table now, rather than waiting for it to go stale
notes-reindex() {
  _notes_reindex && echo "notes: reindexed $NOTES_CACHE"
}

# Apply the moves /wrap recorded
#
# /wrap routes an investigation to a topic, but cannot move the dir it runs in:
# Claude is running there, and a move breaks its paths. So it records
# `move_to` (and optionally `move_as`, the subdir name) in .session.json, and
# this does the move once no Claude process is using the dir. notes(1) calls it
# on the way in, so a wrapped investigation lands in its topic the next time
# you open anything.
#
# Usage: notes-settle [-q]     -q: say nothing about dirs still in use
notes-settle() {
  local quiet=0
  [[ "$1" == "-q" ]] && quiet=1
  [[ -x "$NOTES_BIN/notes-merge" ]] && command -v jq &>/dev/null || return 0

  local -a pending
  pending=( ${(f)"$(grep -l '"move_to"' "$NOTES_DIR"/*/.session.json(N) \
                     "$NOTES_DIR"/*/*/.session.json(N) 2>/dev/null)"} )
  (( ${#pending} )) || return 0

  # The window this shell is in, if it is a notes window.
  # And its session: a top-level dir's move closes all of notes--<slug>, not
  # just one window.
  local here="" here_session=""
  if [[ -n "$TMUX_PANE" ]]; then
    here=$(tmux display -p -t "$TMUX_PANE" '#{@notes}' 2>/dev/null)
    here_session=$(tmux display -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
  fi

  local meta dir rel target sub out tmp moved=0
  for meta in "${pending[@]}"; do
    dir="${meta:h}"
    rel="${dir#$NOTES_DIR/}"
    target=$(jq -r '.move_to // empty' "$meta" 2>/dev/null)
    sub=$(jq -r '.move_as // empty' "$meta" 2>/dev/null)
    [[ -n "$target" ]] || continue

    if [[ "$rel" == "${target}/"* ]]; then
      # Already where it was headed; just clear the marker.
      tmp=$(jq 'del(.move_to, .move_as)' "$meta") && printf '%s\n' "$tmp" > "$meta"
      continue
    fi
    # Never from under the shell running this: the move closes that window,
    # or that whole session for a top-level dir.
    if [[ "$here" == "$rel" || "${PWD:A}" == "${dir:A}" || "${PWD:A}" == "${dir:A}"/* ]] \
       || [[ "$rel" != */* && "$here_session" == "notes--${rel}" ]]; then
      (( quiet )) || print -r -- "notes: not moving ${rel} — this shell is in it"
      continue
    fi

    if out=$("$NOTES_BIN/notes-merge" --target "$target" \
               --absorb "${rel}${sub:+=$sub}" --close-sessions --apply 2>&1); then
      print -r -- "notes: moved ${rel} → ${target}/${sub:-${rel##*/}}"
      (( moved++ ))
    elif [[ "$out" == *"Claude running"* ]]; then
      (( quiet )) || print -r -- "notes: not moving ${rel} yet — Claude is running in it"
    else
      print -r -- "notes: could not move ${rel} into ${target}:"
      print -r -- "  ${${(f)out}[-1]}"
    fi
  done
  (( moved )) && _notes_reindex
  return 0
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
  # A topic dir's root is never pruned here: its investigations are what
  # make it not empty.
  prunable=( ${(f)"$(print -r -- "$index" | jq -r '
    .dirs[]
    | select(.kind != "topic")
    | select(.files == 0 and .transcripts == 0 and (.kb_refs | length) == 0)
    | .slug')"} )
  dangling=( ${(f)"$(print -r -- "$index" | jq -r '
    .dirs[]
    | select(.kind != "topic")
    | select(.files == 0 and .transcripts == 0 and (.kb_refs | length) > 0)
    | "\(.slug)\t\(.kb_refs | join(", "))"')"} )
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
    echo "  → /wrap --recover <old-name> (moved dirs keep their transcript under it)"
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
    if [[ "$slug" == */* ]]; then
      _notes_close_window "$slug"
    else
      tmux kill-session -t "=notes--${slug}" 2>/dev/null
    fi
    rm -rf "${NOTES_DIR}/${slug}"
    echo "  removed ${slug}"
  done
  _notes_reindex
}

# --- Workflow: notes -> code handoff ---

# Resolve the notes dir for the current directory, if we are in one, as its
# path under NOTES_DIR: `<topic>/<slug>` inside an investigation, `<topic>` at
# a topic dir's root (or in a dir that belongs to the root, like scripts/),
# `<slug>` in a dir from before the layout.
_notes_current_slug() {
  local dir="${PWD:A}" root="${NOTES_DIR:A}"
  [[ "$dir" == "$root"/* ]] || return 1
  local rest="${dir#$root/}"
  local top="${rest%%/*}"
  if [[ "$rest" == */* ]] && _notes_is_topic_dir "$top"; then
    local sub="${rest#*/}"
    sub="${sub%%/*}"
    if _notes_is_investigation "$top" "$sub"; then
      print -r -- "${top}/${sub}"
      return
    fi
  fi
  print -r -- "$top"
}

# Close the tmux window of an investigation, leaving the rest of its topic's
# session alone.
_notes_close_window() {
  local rel="$1"
  local session="notes--${rel%%/*}"
  local idx
  idx=$(tmux list-windows -t "=${session}" -F '#{window_index}'$'\t''#{@notes}' 2>/dev/null \
    | awk -F'\t' -v r="$rel" '$2 == r { print $1; exit }')
  [[ -n "$idx" ]] && tmux kill-window -t "=${session}:${idx}" 2>/dev/null
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
#   code <branch> --notes <topic>/<slug>   run from anywhere
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
  for _fn in _worktree_path _notes_session_init _notes_current_slug _notes_is_topic_dir; do
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
  # A topic dir's root is many investigations, not one: linking a worktree to
  # it would leave /wrap no way to tell which one the work came out of.
  if [[ "$notes_slug" != */* ]] && _notes_is_topic_dir "$notes_slug"; then
    echo "code: ${notes_slug} is a topic dir, not an investigation."
    echo "      run it from <topic>/<slug>, or pass --notes ${notes_slug}/<slug>"
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

  # Components are repo-relative paths (<system>/<component>), not bare
  # directory names. `spt git:worktree add -c` accepts a name that
  # matches nothing, writes it as a top-level cone pattern and reports
  # "Worktree ready" — leaving a worktree with none of the code in it.
  if (( is_monorepo && ${#components[@]} )) && command -v spt &>/dev/null; then
    local -a known_components
    known_components=( ${(f)"$(cd -q "$repo_root" && spt git:sparse list-components 2>/dev/null)"} )
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
        "$(cd -q "$repo_root" && _git_default_branch)" ) || return 1
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
    print -r -- "${notes_dir} (available to you via --add-dir). Start with"
    print -r -- "${notes_dir}/HANDOFF.md if it exists; open other files there only"
    print -r -- "when it points you to them or the task needs detail — do not"
    print -r -- "explore the whole dir, and do not re-derive what it concludes."
    print -r -- ""
    print -r -- "Task:"
    print -r -- "$prompt_text"
  } > "$tmpfile"

  # The prompt goes before --add-dir: that flag is variadic and would take the
  # prompt as a second directory, starting Claude with no task.
  _agent_cmd "$mode" "$model"
  tmux send-keys -t "$session_name" \
    "${REPLY} \"\$(cat ${tmpfile})\" --add-dir ${(q)notes_dir} && rm -f ${tmpfile}" Enter

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
#   session  the tmux session name notes/code/review would have used
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

  # Notes windows already open, by the rel path notes(1) tagged them with.
  local -a open_windows
  open_windows=( ${(f)"$(tmux list-windows -a -F '#{@notes}' 2>/dev/null)"} )

  # Every notes dir to consider, as rel paths: a topic dir contributes its
  # root and each investigation in it, anything else just itself.
  local top sub
  local -a notes_rels subs absorbed_subs
  for d in "$NOTES_DIR"/*(/N); do
    top="${d:t}"
    # The reviews dir lives under NOTES_DIR but is not an investigation.
    [[ "${d:A}" == "${REVIEWS_DIR:A}" ]] && continue
    notes_rels+=( "$top" )
    _notes_is_topic_dir "$top" || continue
    absorbed_subs=()
    [[ -f "$d/.session.json" ]] && absorbed_subs=( ${(f)"$(jq -r \
      '(.absorbed // [])[] | (.subdir // .slug)' "$d/.session.json" 2>/dev/null)"} )
    for sub in "$d"/*(/N:t); do
      if [[ -f "$d/$sub/.session.json" ]] || (( ${absorbed_subs[(Ie)$sub]} )); then
        notes_rels+=( "${top}/${sub}" )
      fi
    done
  done

  local d slug sess islive ts ctx flags
  for slug in "${notes_rels[@]}"; do
    d="${NOTES_DIR}/${slug}"

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

    sess="notes--${slug%%/*}"
    islive=0
    if [[ "$slug" == */* ]]; then
      (( ${open_windows[(Ie)$slug]} )) && islive=1
    else
      (( ${live[(I)$sess]} )) && islive=1
    fi
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
# Session names match what notes, code and review would have used, so a
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
  # their own, and worktree-gc is what actually removes them.
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
    if [[ "$kind" == notes ]]; then
      # Back into its topic's session, as the window notes(1) would use.
      _notes_ensure_window "${cwd#$NOTES_DIR/}" || continue
      (( ${created[(Ie)$sess]} )) || created+=( "$sess" )
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
  local -a dirs nested topics
  dirs=( "$NOTES_DIR"/*(/N:t) )
  # Investigations inside topic dirs, as <topic>/<slug>.
  nested=( "$NOTES_DIR"/*/*/.session.json(N:h) )
  nested=( ${nested#$NOTES_DIR/} )
  topics=( "$NOTES_KB"/topics/*.md(N:t:r) )
  _describe -t dirs 'scratch dir' dirs
  _describe -t nested 'investigation' nested
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
