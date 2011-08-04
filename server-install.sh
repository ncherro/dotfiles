test -r ~/.bashrc && mv ~/.bashrc ~/.bashrc.bak;
ln -s ./bashrc-for-linux-servers ~/.bashrc;
test -r ~/.bashrc.local || echo "# use this file to extend ~/.bashrc, which is symlinked to bashrc-for-linux-servers in the dotfiles directory" > ~/.bashrc.local;
test -r ~/.vim && mv ~/.vim ~/.vim.bak
ln -s vim ~/.vim
test -r ~/.vimrc && mv ~/.vimrc ~/.vimrc.bak
ln -s vimrc ~/.vimrc
echo "DONE!"
