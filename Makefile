brews = fd git gh node pnpm ripgrep tree
casks = gpg-suite spotify rectangle slack google-chrome 1password
cocs = coc-css coc-eslint coc-html coc-json coc-lists coc-prettier coc-sh coc-sumneko-lua coc-tsserver coc-vimlsp coc-yaml
npms = @tailwindcss/language-server graphql-language-service-cli
dots = gitconfig gitconfig.local vimrc zprofile zshrc

# --------------------------------------

#/ help            Print this message (default)
help:
	@printf "%sUsage: make TARGET\n"
	@cat ./Makefile | grep '^#\/' | sed "s/#\//  /g"
	@printf "%s\nGlobal packages:\n"
	@printf "%sbrew: $(brews)\n"
	@printf "%scask: $(casks)\n"
	@printf "%scocs: $(cocs)\n"

#/ install         Installs homebrews, casks and dotfiles
install:
	sudo -v
	/opt/homebrew/bin/brew install $(brews)
	/opt/homebrew/bin/brew install neovim
	/opt/homebrew/bin/brew install --cask $(casks)
	@for file in $(dots); do ln -sfv `pwd`/$$file $$HOME/.$$file; done
	@if [[ -d $$HOME/.config/nvim ]]; then rm -rf $$HOME/.config/nvim; fi
	@mkdir -pv $$HOME/.config/nvim
	@ln -sfv `pwd`/coc-settings.json $$HOME/.config/nvim/
	@ln -sfv `pwd`/init.lua $$HOME/.config/nvim/
	@printf "%s\nInstall global npm packages: npm install $(npms) --global"
	@printf "%s\nOpen nvim and (auto)run: :Lazy install"
	@printf "%s\nInstall nvim coc plugins: :CocInstall $(cocs)"
	@printf "%s\nSetup macOS defaults: make macos\n"

#/ uninstall       Removes homebrews, casks and dotfiles
uninstall:
	sudo -v
	brew uninstall $(brews) macvim
	brew uninstall --cask $(casks)
	@rm -rfv $$HOME/.config
	@rm -rfv $$HOME/.local
	@for file in $(dots); do rm -v $$HOME/.$$file; done

#/ update          Updates homebrews and casks
update:
	brew update
	@printf "%s----\n"
	brew outdated
	@printf "%s----\n"
	brew upgrade
	@printf "%s----\n"
	brew cleanup
	@printf "%s----\n"
	brew doctor
	@printf "%s----\n"
	npm update -g $(npms)
	@printf "%sUpdate nvim plugins: :Lazy update, :TSUpdate, :CocUpdate\n"

#/ macos           Setup macOS defaults: https://mths.be/macos
macos:
	sudo -v
	@# Automatically quit printer app once the print jobs complete
	defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
	@# Disable press-and-hold for keys in favor of key repeat
	defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
	@# Set a blazingly fast keyboard repeat rate -- REQUIRES LOGOUT!
	defaults write NSGlobalDomain KeyRepeat -int 1
	defaults write NSGlobalDomain InitialKeyRepeat -int 15
	@# Save screenshots to the desktop
	defaults write com.apple.screencapture location -string "${HOME}/Downloads"
	@# Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
	defaults write com.apple.screencapture type -string "png"
	@# Disable shadow in screenshots
	defaults write com.apple.screencapture disable-shadow -bool true
	@# Finder: allow text selection in Quick Look
	defaults write com.apple.finder QLEnableTextSelection -bool true
	@# Avoid creating .DS_Store files on network volumes
	defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
	@# Show the ~/Library folder
	chflags nohidden ~/Library
	@# Make Dock icons of hidden applications translucent
	defaults write com.apple.dock showhidden -bool true

.PHONY: help install uninstall update macos
