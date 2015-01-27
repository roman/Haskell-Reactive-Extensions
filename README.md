# Haskell Reactive Extensions

This is an experimental implementation of Rx in Haskell

## Example

Using a sync scheduler:

```haskell

module Main where

import qualified Rx.Observable as Rx

main :: IO ()
main = do
  let source = Rx.fromList Rx.currentThread [1..10]
  result <- Rx.subscribe print print (putStrLn "Stream Done")
```

Using an async scheduler (can only compose monadically through async):

```haskell

import Control.Applicative
import Control.Lens

import Data.Text
import Data.Monoid ((<>))

import Data.Aeson.Lens
import Network.Wreq

import qualified Rx.Observable as Rx

getWeather :: Text -> IO (Maybe Text)
getWeather cityLocation = do
  let opts = defaults & param "q" .~ [cityLocation]
  response <- getWith opts "http://api.openweathermap.org/data/2.5/weather"
  let mcity = response ^? responseBody . key "name" . _String
      mtemp = response ^? responseBody . key "weather" . nth 0 . key "description" . _String
      result = do
        city <- mcity
        temp <- mtemp
        return (temp <> " in " <> city)
  return result

cityMatch :: Rx.Observable Rx.Async (Maybe Text, Maybe Text)
cityMatch =
  (,) <$> Rx.toAsyncObservable (getWeather "Vancouver, BC")
      <*> Rx.toAsyncObservable (getWeather "Toronto, ON")

main :: IO ()
main = do
  result <- Rx.toEither cityMatch
  print result

```

## LICENSE

```
Copyright (c) 2014-2015, Roman Gonzalez

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

```
