#!/bin/sh

root=$(realpath $(dirname $0)/..)
ghc -odir $root/build -hidir $root/build -O2 -threaded -with-rtsopts=-N -i$root $root/Main.hs -o $root/Seeker
clang++ -std=c++11 -O2 $root/Seeker-8.6.cpp -o $root/Seeker-8.6
