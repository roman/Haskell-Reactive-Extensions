{-# LANGUAGE OverloadedStrings #-}
module Rx.Logger.LogLevelParser where

import           Control.Applicative  (pure, (*>), (<$>), (<*))
import qualified Data.Attoparsec.Text as Atto
import           Data.List            (foldl1')
import qualified Data.Text            as Text

import Rx.Logger.Types


pLogLevel :: Atto.Parser LogLevel
pLogLevel =
  Atto.choice [
      Atto.asciiCI "noisy"   *> pure NOISY
    , Atto.asciiCI "loud"    *> pure LOUD
    , Atto.asciiCI "trace"   *> pure TRACE
    , Atto.asciiCI "config"  *> pure CONFIG
    , Atto.asciiCI "info"    *> pure INFO
    , Atto.asciiCI "warning" *> pure WARNING
    , Atto.asciiCI "severe"  *> pure SEVERE
    ]

pLogLevelFn :: Atto.Parser (LogLevel -> Bool)
pLogLevelFn = do
    cmpFn <- pFn <* Atto.skipSpace
    level <- pLogLevel
    return $ flip cmpFn level
  where
    pFn =
      Atto.option (==)
        $ Atto.choice [ Atto.string "<=" *> return (<=)
                      , Atto.string ">=" *> return (>=)
                      , Atto.char   '>'  *> return (>)
                      , Atto.char   '<'  *> return (<) ]


pLogLevels :: Atto.Parser (LogLevel -> Bool)
pLogLevels =
  Atto.choice [
    combineFns
      <$> Atto.sepBy1 pLogLevelFn
                      (Atto.skipSpace
                       *> Atto.char ','
                       <* Atto.skipSpace)
      <* Atto.endOfInput
    , Atto.skipSpace *> Atto.asciiCI "none" *> pure (const False)
    ]
  where
    combineFns =
      foldl1'
      (\predFn thisFn ->
        \log -> predFn log || thisFn log)


parseLogLevel :: Text.Text -> Maybe (LogLevel -> Bool)
parseLogLevel input =
  case Atto.parseOnly pLogLevels input of
    Left _ -> Nothing
    Right pred -> Just pred
