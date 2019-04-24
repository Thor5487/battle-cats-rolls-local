
module Seed
  ( Seed(Seed)
  , SeedValue
  , fromSeed
  , advanceSeed
  , matchRoll
  , minSeedValue) where

import Data.Bits (xor, shiftL, shiftR)
import Data.Word (Word32)
import Control.Monad (guard, liftM2)

import Roll

newtype Seed = Seed { fromSeed :: Word32 } deriving (Show, Eq)
type SeedValue = Seed -> Word32

advanceSeed :: Seed -> Seed
advanceSeed =
  Seed .
  (step (`shiftL` 15)) .
  (step (`shiftR` 17)) .
  (step (`shiftL` 13)) .
  fromSeed

matchRoll :: Seed -> SeedValue -> Roll -> Maybe Seed
matchRoll seed seedValue (Roll rarity@(Rarity _ _ count) slot) = do
  matchRarity seed seedValue rarity
  matchSlot (advanceSeed seed) seedValue count slot

matchRarity :: Seed -> SeedValue -> Rarity -> Maybe Seed
matchRarity seed seedValue (Rarity begin end _) = do
  guard $ score >= begin && score < end
  return seed
  where
    score = (seedValue seed) `mod` scoreBase

matchSlot :: Seed -> SeedValue -> Word32 -> Slot -> Maybe Seed
matchSlot seed seedValue count slot = do
  guard $
    case slot of
      Slot slotCode ->
        seedCode == slotCode
      DualSlot slotCode dupeCode ->
        seedCode == slotCode || seedCode == dupeCode

  return seed

  where
    seedCode = (seedValue seed) `mod` count

step :: (Word32 -> Word32) -> Word32 -> Word32
step direction seed = seed `xor` (direction seed)

minSeedValue :: Seed -> Word32
minSeedValue (Seed seed) = min seed (alternativeSeed seed)

alternativeSeed :: Word32 -> Word32
alternativeSeed seed = 0xffffffff - seed + 1

------------------------------------------------

-- seed = Seed 1745107336
-- tests =
--   [ advanceSeed seed == Seed 2009320978
--   , matchRarity seed (Rarity 7000 9000 1)
--   , not $ matchRarity seed (Rarity 0 7000 1)
--   , matchSlot seed 10 (Slot 6)
--   , not $ matchSlot seed 10 (Slot 7)
--   , matchRoll seed (Roll (Rarity 7000 9000 100) (Slot 78))
--   ]

-- test = foldr (&&) True tests
