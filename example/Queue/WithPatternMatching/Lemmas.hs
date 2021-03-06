module Queue.WithPatternMatching.Lemmas where

import           Test.QuickCheck

import           Queue.WithPatternMatching.Queue
import           Queue.WithPatternMatching.QueueI
import           Queue.WithPatternMatching.Util

prop_is_pure_true_or :: Bool -> Bool -> Property
prop_is_pure_true_or b1 b2 = b1 || b2 ==> property b1 .||. property b2

prop_is_pure_true_and :: Bool -> Bool -> Property
prop_is_pure_true_and b1 b2 = b1 && b2 ==> property b1 .&&. property b2

prop_null_rev :: [a] -> Property
prop_null_rev xs = null xs ==> property (null (reverse xs))

prop_append_nil :: [a] -> Property
prop_append_nil xs = xs `append` [] === xs

prop_append_assoc :: [a] -> [a] -> [a] -> Property
prop_append_assoc xs ys zs =
  xs `append` (ys `append` zs) === (xs `append` ys) `append` zs
