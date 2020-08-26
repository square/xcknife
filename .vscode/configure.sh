#!/bin/bash

CWD=$(pwd)

if [[ "$CWD" == *".vscode"* ]] ; then
  cd ..
fi

RSPEC_PATH="$(command -v rspec)"
BUNDLE_PATH="$(command -v bundle | sed 's/bin/wrappers/')"
RDEBUG_PATH=$(cd ./ || exit 1; bundle show ruby-debug-ide)

if [ -z "$RSPEC_PATH" ] || [ -z "$BUNDLE_PATH" ] || [ -z "$RDEBUG_PATH" ]; then
  echo "error: Missing required gem, please run 'bundle install'"
  exit 1
fi

echo "Using configuration paths:"
echo "$RSPEC_PATH"
echo "$BUNDLE_PATH"
echo "$RDEBUG_PATH"

cat < "./.vscode/vscode_ruby.json.template" | sed "s|RSPEC_PATH|$RSPEC_PATH|g" | sed "s|BUNDLE_PATH|$BUNDLE_PATH|g" | sed "s|RDEBUG_PATH|$RDEBUG_PATH|g" > ./.vscode/launch.json
