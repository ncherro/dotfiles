test -r ~/.gvimrc.local && mv ~/.gvimrc.local ~/.gvimrc.local.bak;
test -r ~/.vimrc.local && mv ~/.vimrc.local ~/.vimrc.local.bak;
test -r ~/.janus.rake && mv ~/.janus.rake ~/.janus.rake.bak;
ln -s ./gvimrc.local ~/.gvimrc.local; ln -s ./vimrc.local ~/.vimrc.local; ln -s ./janus.rake ~/.janus.rake;
echo "DONE!"
