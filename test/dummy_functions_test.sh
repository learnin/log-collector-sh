#!/bin/sh
set -u

ln -s $$ $1 2> /dev/null
sleep $2
