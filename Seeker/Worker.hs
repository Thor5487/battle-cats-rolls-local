
module Worker where

import Control.Concurrent

import Roll
import Seed
import Seeker

workStart :: Source -> Int -> IO (Maybe SeekResult)
workStart source n = do
  result <- newEmptyMVar
  threads <- sequence $ dispatch source (seedRanges n) result
  -- putStrLn $ show $ length threads
  forkIO $ do
    wait threads
    tryPutMVar result Nothing >> return ()
  takeMVar result

  where
    wait :: [MVar ()] -> IO ()
    wait = mapM_ takeMVar

seedRanges :: Int -> [Seed]
seedRanges n =
  map Seed $ [min, min + step .. (max - step)] ++ [max] where
  min = fromSeed minSeed
  max = fromSeed maxSeed
  step = floor $ toRational max / (toRational n / 2)

dispatch :: Source -> [Seed] -> MVar (Maybe SeekResult) -> [IO (MVar ())]
dispatch source ranges result =
  map dispatchOne allRanges where
  allRanges = zip ranges (tail ranges)
  dispatchOne (start, end) = work source start end result

work :: Source -> Seed -> Seed -> MVar (Maybe SeekResult) -> IO (MVar ())
work source startSeed endSeed result =
  forkWithMVar $ do
    case seekRange (buildSeekStep source) startSeed endSeed of
      Nothing -> return ()
      seed@(Just _) -> tryPutMVar result seed >> return ()

forkWithMVar :: IO () -> IO (MVar ())
forkWithMVar io = do
  terminated <- newEmptyMVar
  forkFinally io (const (putMVar terminated ()))
  return terminated
