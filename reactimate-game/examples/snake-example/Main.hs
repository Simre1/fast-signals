{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

import Control.Monad (when)
import Data.Colour.Names (red)
import Data.Colour.SRGB (sRGB24)
import Data.Foldable (toList)
import Data.List (group)
import Data.Vector.Storable qualified as VS
import Reactimate
import Reactimate.Game
import SDL qualified

gameConfig :: GameConfig
gameConfig =
  GameConfig
    { name = "Snake",
      window = defaultWindow {windowInitialSize = fromIntegral . (* 30) <$> gameBounds},
      fps = 11
    }

main :: IO ()
main = reactimate $ setupGame gameConfig $ \gameEnv ->
  captureInput gameEnv >>> (feedback (initialGameState 0) stepGame >>> printScore &&& render gameEnv) &&& shouldQuit >>> arr snd

data Input = MoveLeft | MoveRight | MoveUp | MoveDown | NoAction | Quit deriving (Eq, Ord, Show)

data GameState = GameState
  { snake :: [V2 Int],
    direction :: V2 Int,
    food :: Maybe (V2 Int),
    running :: Bool,
    score :: Int
  }

captureInput :: GameEnv -> Signal () Input
captureInput gameEnv =
  sampleEvent collectInput [] (inputEvents gameEnv)
    >>> feedback [] (arr $ \(newActions, oldActions) -> fmap head $ group $ drop 1 oldActions ++ newActions)
    >>> arr
      ( \case
          (i : _) -> i
          [] -> NoAction
      )
  where
    collectInput [Quit] _ = [Quit]
    collectInput is event = case SDL.eventPayload event of
      SDL.QuitEvent -> [Quit]
      SDL.KeyboardEvent keyboardEvent ->
        if SDL.keyboardEventKeyMotion keyboardEvent == SDL.Pressed
          then case SDL.keysymScancode $ SDL.keyboardEventKeysym keyboardEvent of
            SDL.ScancodeLeft -> is ++ [MoveLeft]
            SDL.ScancodeRight -> is ++ [MoveRight]
            SDL.ScancodeUp -> is ++ [MoveUp]
            SDL.ScancodeDown -> is ++ [MoveDown]
            _ -> is
          else is
      _ -> is

initialGameState :: Int -> GameState
initialGameState score =
  GameState
    { snake = [V2 5 5],
      direction = V2 1 0,
      food = Just (V2 10 10),
      running = False,
      score
    }

gameBounds :: V2 Int
gameBounds = V2 32 18

stepGame :: Signal (Input, GameState) GameState
stepGame =
  generateRandomRange (V2 1 1, gameBounds - V2 2 2)
    &&& identity
    >>> arr
      ( \(rngV2, (input, GameState snake direction food running score)) ->
          if running
            then
              let nextDirection = adaptDirection input direction
                  nextHead = nextDirection + head snake
                  snakeEats = Just nextHead == food
                  nextSnake = shortenSnake food (nextHead : snake)
                  nextFood = if snakeEats then Just rngV2 else food
                  nextScore = if snakeEats then score + 1 else score
               in if isDead nextSnake
                    then initialGameState score
                    else GameState nextSnake nextDirection nextFood True nextScore
            else
              if shouldStartGame input
                then GameState snake direction food True score
                else GameState snake direction food False 0
      )
  where
    shouldStartGame i = case i of
      MoveLeft -> True
      MoveRight -> True
      MoveUp -> True
      MoveDown -> True
      _ -> False
    shortenSnake _ [] = []
    shortenSnake _ [x] = [x]
    shortenSnake foodPos (x : xs) =
      if Just x == foodPos
        then x : xs
        else init (x : xs)
    isDead snake =
      let snakeHead@(V2 x y) = head snake
          (V2 maxX maxY) = gameBounds
       in snakeHead `elem` tail snake || x < 0 || x >= maxX || y < 0 || y >= maxY
    adaptDirection i d =
      let wantedDirection = case i of
            MoveLeft -> V2 (-1) 0
            MoveRight -> V2 1 0
            MoveUp -> V2 0 1
            MoveDown -> V2 0 (-1)
            _ -> d
       in if wantedDirection + d == V2 0 0 then d else wantedDirection

render :: GameEnv -> Signal GameState ()
render gameEnv = arr (\gs -> (camera, gameStatePicture gs)) >>> renderGame gameEnv
  where
    gameStatePicture (GameState snake _ food _ _) =
      makePicture 0 (BasicShapes $ VS.fromList (zipWith snakeShape [0 ..] (toList snake)))
        <> foldMap (makePicture 0 . (BasicShapes . VS.singleton . foodShape)) food
    snakeShape (i' :: Int) pos =
      let i = fromIntegral $ abs $ (i' `mod` 160) - 80
       in ColouredShape (packColour $ sRGB24 0 (255 - i * 2) (i * 3)) $ BSRectangle (Rectangle pos (V2 1 1))
    foodShape pos = ColouredShape (packColour red) $ BSRectangle (Rectangle pos (V2 1 1))
    camera = Camera (V2 0 0) gameBounds

printScore :: Signal GameState ()
printScore = (>>> constant ()) $ feedback False $ arrIO $ \(gameState, alivePreviously) -> do
  when (not gameState.running && alivePreviously) $
    putStrLn $
      "Score: " ++ show gameState.score
  pure gameState.running

shouldQuit :: Signal Input (Maybe ())
shouldQuit = arr $ \i -> if i == Quit then Just () else Nothing
