ECHO "SYMLINKING CONFIG FILES"

test -r ~/.gvimrc.before && mv ~/.gvimrc.before ~/.gvimrc.before.bak;
test -r ~/.gvimrc.after && mv ~/.gvimrc.after ~/.gvimrc.after.bak;
test -r ~/.vimrc.before && mv ~/.vimrc.before ~/.vimrc.before.bak;
test -r ~/.vimrc.after && mv ~/.vimrc.after ~/.vimrc.after.bak;
test -r ~/.janus && mv ~/.janus ~/.janus.bak;
test -r ~/.tmux.conf && mv ~/.tmux.conf ~/.tmux.conf.bak;

ln -s `pwd`/gvimrc.before ~/.gvimrc.before;
ln -s `pwd`/gvimrc.after ~/.gvimrc.after;
ln -s `pwd`/vimrc.before ~/.vimrc.before;
ln -s `pwd`/vimrc.after ~/.vimrc.after;
ln -s `pwd`/janus ~/.janus;
ln -s `pwd`/tmux.conf ~/.tmux.conf;

echo "Setting up git aliases"

git config --global alias.co checkout;
git config --global alias.br branch;
git config --global alias.ci commit;
git config --global alias.st status;

echo "DONE!"
