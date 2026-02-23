#!/bin/sh
# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)

# test CGI program, this remains portable POSIX shell (not bash)
set -e

stdhead () {
	echo Content-Type: text/plain
	echo Status: 200 OK
	echo
}

case $PATH_INFO in
/)
	stdhead
	echo HIHI
	;;
/env)
	stdhead
	env
	;;
/pid)
	stdhead
	echo $$
	;;
/die)
	if test -n "$HTTP_X_PID_DEST"
	then
		# obviously this is only for testing on a local machine:
		echo $$ > "$HTTP_X_PID_DEST"
		exit 1
	else
		echo Content-Type: text/plain
		echo Status: 400 Bad Request
		echo Content-Length: 0
		echo
	fi
	;;
/known-length)
	echo Content-Type: text/plain
	echo Status: 200 OK
	echo Content-Length: 5
	echo
	echo HIHI
	;;
*)
	echo Content-Type: text/plain
	echo Status: 404 Not Found
	echo
	;;
esac
