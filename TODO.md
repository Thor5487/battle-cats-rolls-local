## Top priority

* Eliminate next_seed

## Features and utilities

* Use browser timezone offset to calculate local time
* Update event data for each 11 hours automatically
* Tracking history (by recording rolls we click)
* Find a better event when switching languages with an invalid event

## Architecture

* Use server-sent event to pull seek result
* Queue in memcached rather than in-process! Otherwise can't do great
  zero down time restarting.

## Build script, language and APK

* Make fetching APK optional as long as the YAML is built already
* Verify APK checksum
* Only show the languages which are built, no need to force all of them

## Tests

* Check 2160402177
* echo 8.5 6970 2500 500 30 23 21 7 1 3 20 2 15 2 22 2 12 3 16 2 8 2 0 2 15 3 19 5 0 | time ./Seeker
* Above is 1027349002
* Picking an invalid event
* 3112486085 is a very nice testing seed

## Seed seeker

* An idea to speed up seeking process. We could pre-process the seeds, and
  create 10 rarity patterns saved in files. Say, starting with seed 1,
  the following rarity will be: R, S, R, R, U, R, and so on, we append the
  seed 1 to the file RSRRUR. We repeat this process for all the seeds, ending
  up with tons of files recoding all the seeds of possible patterns. This
  way, we could use the input rarity pattern to find the corresponding files,
  and only search for those seeds. It could be multiple files because the
  input might not have enough rolls. We should record for 10 rolls pattern,
  say RSRRURSRRU, and RSRRURSRRS (only the last one is different). And the
  input could be just 9 rolls like RSRRURSRR, then we should search for
  both files because they both match the same prefix pattern.
