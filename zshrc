export DOTFILES=~/Projects/dotfiles

case "$(uname -s)" in
  Darwin) source $DOTFILES/zsh/mac.zsh ;;
  Linux)  source $DOTFILES/zsh/linux.zsh ;;
esac

source $DOTFILES/zsh/base.zsh

# Machine-local overrides (gitignored)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
