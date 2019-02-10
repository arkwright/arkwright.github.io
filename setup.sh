# Sets up Jekyll
brew install rbenv
eval "$(rbenv init -)"
rbenv install 2.6.1
rbenv local 2.6.1
gem install bundler
bundle install
# bundle exec jekyll serve
