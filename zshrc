export DOTFILES=~/Projects/dotfiles

case "$(uname -s)" in
  Darwin) source $DOTFILES/zsh/mac.zsh ;;
  Linux)  source $DOTFILES/zsh/linux.zsh ;;
esac

source $DOTFILES/zsh/base.zsh

# Spotify devex tooling (auto-managed by path_updater_lib.sh — do not remove)
export PATH=/opt/spotify-devex/bin:$PATH

# Machine-local overrides (gitignored)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
