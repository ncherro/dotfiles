mv ~/.gvimrc.local ~/.gvimrc.local.bak; mv ~/.vimrc.local ~/.vimrc.local.bak; mv ~/.janus.rake ~/.janus.rake.bak;
ln -s ./.gvimrc.local ~/.gvimrc.local; ln -s ./.vimrc.local ~/.vimrc.local; ln -s ./.janus.rake ~/.janus.rake;
echo "DONE!"
