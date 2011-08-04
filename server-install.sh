test -r ~/.bashrc && mv ~/.bashrc ~/.bashrc-bak;
ln -s ./bashrc-for-linux-servers ~/.bashrc;
test -r ~/.bashrc.local || echo "# use this file to extend ~/.bashrc, which is a symlink" > ~/.bashrc.local;
echo "DONE!"
