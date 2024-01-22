import Control.Arrow (Arrow (..))
import Control.Category ((>>>))
import Data.MonadicStreamFunction qualified as MSF
import Data.MonadicStreamFunction.InternalCore qualified as MSF
import Data.SF.Combinators qualified as SF
import Data.SF.Run qualified as SF
import Data.SF.Time qualified as SF
import FRP.Yampa qualified as Y
import Test.BenchPress (benchMany)
import Data.Foldable (Foldable(..))

count :: Int
count = 100000

-- this is not super realistic since Yampa does some time calculation as well
yampaCountBench :: IO ()
yampaCountBench = do
  Y.reactimate
    (pure ())
    (\_ -> pure (0, Just ()))
    (\_ !b -> if b == 0 then pure True else pure False)
    (Y.loopPre count (arr (\((), !x) -> (x - 1, x - 1))))

sfCountBench :: IO ()
sfCountBench = do
  !x <- SF.reactimate (SF.feedback count (arr (\((), !x) -> (x - 1, x - 1))) >>> arr (\x -> if x == 0 then Just x else Nothing)) ()
  pure ()

msfCountBench :: IO ()
msfCountBench = do
  !x <- reactimate $ MSF.feedback count (arr (\((), !x) -> (x - 1, x - 1))) >>> arr (\x -> if x == 0 then Just x else Nothing)
  pure ()
  where
    reactimate :: MSF.MSF IO () (Maybe a) -> IO a
    reactimate msf = do
      (b, next) <- MSF.unMSF msf ()
      case b of
        Nothing -> reactimate next
        Just x -> pure x

integrateSamples :: Int
integrateSamples = 10000000

yampaIntegrateBench :: IO ()
yampaIntegrateBench = do
  !x <- pure $ last (Y.embed (pure (1 :: Double) >>> Y.integral) (Y.deltaEncode 0.1 [1 .. integrateSamples]))
  pure ()

newtype Env = Env
  { time :: SF.Time
  }

sfIntegrateBench :: IO ()
sfIntegrateBench = do
  !x <-
    SF.fold
      (\_ x -> x)
      0
      (SF.withFixedTime 0.1 (\_ t -> Env t) $ pure 1 >>> SF.integrate (*))
      ()
      [1 .. integrateSamples]
  pure ()

chainTest :: Arrow a => a Double Double
chainTest = foldl' (\a _ -> a >>> a) (arr (+1)) [0..16]

yampaChainBench :: IO ()
yampaChainBench = do
  let !x = head $ Y.embed chainTest (0, [])
  pure ()

sfChainBench :: IO ()
sfChainBench = do
  !x <- head <$> SF.sample chainTest () [0]
  pure ()

msfChainBench :: IO ()
msfChainBench = do
  !x <- head <$> MSF.embed chainTest [0]
  pure ()

main :: IO ()
main = do
  putStrLn "Countdown benchmark"
  benchMany 20 [("Yampa", yampaCountBench), ("dunai", msfCountBench), ("fast-signals", sfCountBench)]
  putStrLn ""
  putStrLn "Integrate benchmark"
  benchMany 1 [("Yampa", yampaIntegrateBench), ("fast-signals", sfIntegrateBench)]
  putStrLn ""
  putStrLn "Chaining (>>>) benchmark"
  benchMany 20 [("Yampa", yampaChainBench), ("dunai", msfChainBench), ("fast-signals", sfChainBench)]

