## Stats

* Show talents
* Account surge damage into DPS
* Show surge duration
* Show knockback distance
* Show slow percentage
* Use consistent unit for speed (range per second)
* Figure out how where to find the hard coded values in the game data

## Bugs

* Preserve current queries when swapping language for a non-existing cat when showing stats
* If there's a non-existing cat in a gacha, for now we show nothing because
  tracking can't be done due to missing rarity data. However, it'll be useful
  to show the gacha data so we know it's not just an empty gacha but a gacha
  we can't use, and it should be clear what's the missing cat so we have a
  better idea. See:
  https://bc.godfat.org/?seed=1&event=custom&custom=12&details=true
  This should not show empty gacha, but what are there and what's missing.
  Check GachaPool#slots for this.
* Can't untick the last owned cat (This is because we can't tell if this is
  visiting the page itself or it's unticking the last cat, because `t` is
  absent in both cases, the URL is the same!)
* Fix guessing 10 rolls link when seeking seed (Can't recall this. Was this for dupe rare?)

## Features and utilities

* Localize default customized rate. superfest -> 超極ネコ祭
* Finishing the help page
* Multi-select for finding cats
* Retreat seed
* Client-side seed seeker
* Don't use the hard coded version. Check on the disk and see if there's
  a newer version apk and use that instead.
* Show multiple instances horizontally so we can look at different events
  at the same time! Each can take different seeds.
* Tracking history (by recording rolls we click)
* Use browser timezone offset to calculate local time

## Architecture

* Queue in memcached rather than in-process! Otherwise can't do great
  zero down time restarting. But we might want to find a way to clear
  the queue without clearing the whole memcached.

## Build script, language and APK

* Only show the languages which are built, no need to force all of them

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
