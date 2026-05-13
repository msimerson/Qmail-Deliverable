#!/bin/sh

VERSION=$1
if [ -z "$VERSION" ]; then
	echo "$0 ver1 ver2"
	exit 2
fi
if [ -z "$2" ]; then
	echo "$0 ver1 ver2"
	exit 2
fi

# Escape dots so the version strings are safe to embed in regex patterns.
escaped1=$(printf '%s' "$1" | sed 's/\./\\./g')
escaped2=$(printf '%s' "$2" | sed 's/\./\\./g')

gfind() {
	find . -type d \( -name .git -o -name .build -o -name .github \) -prune \
	     -o -type f -print
}

grep -Fl "$VERSION" $(gfind) | sort -u > versions.txt
perl -pi -e "s/\b$escaped1\b/$2/g if /version|VERSION|v$escaped1/" $(cat versions.txt)
rm versions.txt
