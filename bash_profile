if [[ -f $HOME/.bashrc ]]; then source $HOME/.bashrc; fi
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN
