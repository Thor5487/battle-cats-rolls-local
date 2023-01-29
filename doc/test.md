
# Test the following edge cases:

## Tracking

* Existing dupes can cause more dupes, see this for bouncing around:
  https://bc.godfat.org/?seed=2263031574&event=2019-11-27_377&pick=5AR#N5A
* A lot of dupes in a row:
  * 2: https://bc.godfat.org/?seed=2458231674&event=2019-07-18_391&pick=4AX
  * 2: https://bc.godfat.org/?seed=2116007321&event=2019-07-21_391&pick=1AG
  * 3: https://bc.godfat.org/?seed=1773704064&event=2020-12-11_563&lang=jp&pick=3AR
  * 3: https://bc.godfat.org/?seed=1773704064&event=2020-12-11_563&lang=jp&pick=6BR
  * 4: https://bc.godfat.org/?seed=4229260466&last=496&event=2020-12-11_563&lang=jp&pick=5BR
  * 4: https://bc.godfat.org/?seed=1204266455&last=562&event=2020-12-11_563&lang=jp&pick=4AR
  * 5: https://bc.godfat.org/?seed=4275004160&event=2020-12-11_563&lang=jp&pick=5AR
  * 5: https://bc.godfat.org/?seed=2810505815&event=2020-12-11_563&lang=jp&pick=4BR
  * 2 into R: https://bc.godfat.org/?seed=3322538705&event=2020-12-11_563&lang=jp&pick=8AR
* Tracks from both sides can attempt to reroll the same cat:
  https://bc.godfat.org/?seed=3785770978&event=2020-03-20_414&pick=10AX#N10A
* Picking cannot reach from the beginning:
  * https://bc.godfat.org/?seed=3419147157&event=2019-07-21_391&pick=44AX#N44A
  * https://bc.godfat.org/?seed=3419147157&event=2019-07-21_391&pick=44AGX#N44A
* This can see picking A and B are passing each other:
  https://bc.godfat.org/?seed=2390649859&event=2019-06-06_318
* Highlight partial cell for the part which will be rolled:
  * https://bc.godfat.org/?seed=650315141&last=50&event=2020-09-11_433&pick=2BGX#N2B
  * https://bc.godfat.org/?seed=3626964723&last=49&event=2020-09-11_433&pick=2BGX#N2B

## Stats

* Awakened Bahamut Cat: Multi area attacks:
  https://bc.godfat.org/cats/26
* Apple Cat: Single single attack and single area attack:
  https://bc.godfat.org/cats/40
* Sea Maiden Ruri: Multi single attacks:
  https://bc.godfat.org/cats/336
* Volley Cat: Long range single attack:
  https://bc.godfat.org/cats/380
* Wonder MOMOCO: First strike wave and stop effect:
  https://bc.godfat.org/cats/456
* Ken: Third strike effect with all range:
  https://bc.godfat.org/cats/518
* Kyosaka Nanaho: Second strike critical effect:
  https://bc.godfat.org/cats/545
* Fabled Adventure Girl Kanna: First strike surge effect and various ranges:
  https://bc.godfat.org/cats/608
* Goddess of Light Sirius: Complex attack timing:
  http://bc.godfat.org/cats/687
* Child of Destiny Phono: Very narrow max DPS area:
  http://bc.godfat.org/cats/691
