# Haskell Reactive Extensions

[![CircleCI](https://circleci.com/gh/roman/Haskell-Reactive-Extensions.svg?style=shield&circle-token=:circle-token)](https://circleci.com/gh/roman/Haskell-Reactive-Extensions)

This is an experimental implementation of Rx in Haskell

## Example

Using a sync scheduler:

```haskell

module Main where

import qualified Rx.Observable as Rx

main :: IO ()
main = do
  let source = Rx.fromList Rx.currentThread [1..10]
  result <- Rx.subscribe source print print (putStrLn "Stream Done")

```

Using an async scheduler (can only compose monadically through async):

```haskell

module Main where

import Control.Applicative ((<$>), (<*>))
import Control.Lens ((&), (.~), (^?))

import Data.Monoid ((<>))
import Data.Text (Text)

import Data.Aeson.Lens (key, nth, _String)
import Network.Wreq (defaults, getWith, param, params, responseBody)

import qualified Rx.Observable as Rx

-- Perform an HTTP Request synchronously to get weather of a city
--
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

-- Perform asynchronously two HTTP Request by transforming them into
-- Observables and then compose them
--
cityMatch :: Rx.Observable Rx.Async (Maybe Text, Maybe Text)
cityMatch =
  (,) <$> Rx.toAsyncObservable (getWeather "Vancouver, BC")
      <*> Rx.toAsyncObservable (getWeather "Toronto, ON")

main :: IO ()
main = do
  -- Get Async result into an Either value (uses Rx.subscribe + MVar)
  -- internally
  result <- Rx.toEither cityMatch
  print result

```

## Benchmarks

Running benchmarks through [criterion](https://github.com/roman/Haskell-Reactive-Extensions/blob/master/rx-core/bench/RxBenchmark.hs)

```
benchmarking foldl'
time                 3.470 ms   (3.291 ms .. 3.588 ms)
                     0.983 R²   (0.972 R² .. 0.991 R²)
mean                 3.347 ms   (3.258 ms .. 3.446 ms)
std dev              319.3 μs   (238.6 μs .. 444.6 μs)
variance introduced by outliers: 63% (severely inflated)

benchmarking Rx.foldLeft/withtout contention
time                 37.23 ms   (36.70 ms .. 37.68 ms)
                     0.999 R²   (0.998 R² .. 1.000 R²)
mean                 38.02 ms   (37.72 ms .. 38.42 ms)
std dev              723.5 μs   (565.0 μs .. 962.5 μs)

benchmarking Rx.foldLeft/with contention (10 threads)
time                 492.7 ms   (466.7 ms .. 511.2 ms)
                     1.000 R²   (0.999 R² .. 1.000 R²)
mean                 472.6 ms   (468.7 ms .. 479.3 ms)
std dev              5.862 ms   (0.0 s .. 6.129 ms)
variance introduced by outliers: 19% (moderately inflated)

benchmarking Rx.foldLeft/with contention (100 threads)
time                 553.1 ms   (434.6 ms .. 664.5 ms)
                     0.994 R²   (0.979 R² .. 1.000 R²)
mean                 549.2 ms   (531.3 ms .. 564.0 ms)
std dev              23.45 ms   (0.0 s .. 25.63 ms)
variance introduced by outliers: 19% (moderately inflated)

benchmarking Rx.foldLeft/with contention (1000 threads)
time                 830.6 ms   (NaN s .. 1.059 s)
                     0.976 R²   (0.921 R² .. 1.000 R²)
mean                 870.0 ms   (809.0 ms .. 911.0 ms)
std dev              61.63 ms   (0.0 s .. 71.16 ms)
variance introduced by outliers: 20% (moderately inflated)

benchmarking Rx.foldLeft/with contention (100000 threads)
time                 747.4 ms   (674.0 ms .. 799.5 ms)
                     0.999 R²   (0.996 R² .. 1.000 R²)
mean                 758.7 ms   (747.1 ms .. 766.9 ms)
std dev              12.24 ms   (0.0 s .. 14.08 ms)
variance introduced by outliers: 19% (moderately inflated)

benchmarking Rx.merge/with contention (10000 threads)
time                 86.74 ms   (81.61 ms .. 92.94 ms)
                     0.993 R²   (0.983 R² .. 0.999 R²)
mean                 83.18 ms   (81.16 ms .. 85.76 ms)
std dev              3.754 ms   (2.222 ms .. 5.790 ms)
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
