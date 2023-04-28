#!/bin/sh

root=$(realpath $(dirname $0)/..)
clang++ -std=c++11 -O2 $root/Seeker-8.6.cpp -o $root/Seeker-8.6
