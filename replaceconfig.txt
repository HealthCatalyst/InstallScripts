#!/bin/bash

# usage: replaceconfig.sh <configname> <newvalue> <filename>

sed -i "s#^\($1\s*=\).*\$#\1 $2#" $3
