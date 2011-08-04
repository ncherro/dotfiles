echo "Symlinking rc files"
test -r ~/.gvimrc.local && mv ~/.gvimrc.local ~/.gvimrc.local.bak;
test -r ~/.vimrc.local && mv ~/.vimrc.local ~/.vimrc.local.bak;
test -r ~/.janus.rake && mv ~/.janus.rake ~/.janus.rake.bak;
ln -s `pwd`/gvimrc.local ~/.gvimrc.local; ln -s `pwd`/vimrc.local ~/.vimrc.local; ln -s `pwd`/janus.rake ~/.janus.rake;
echo "Setting up git aliases"
git config --global alias.co checkout;
git config --global alias.br branch;
git config --global alias.ci commit;
git config --global alias.st status;
echo "DONE!"
