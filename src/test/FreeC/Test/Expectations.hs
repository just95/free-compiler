-- | This module contains commonly used expectation setters for the
--   comparison of IR AST nodes.
--
--   TODO should we maybe re-export "FreeC.Monad.Class.Testable"?

module FreeC.Test.Expectations
  ( -- * Similarity test
    shouldBeSimilarTo
  , shouldNotBeSimilarTo
    -- * Pretty printing comparision
  , prettyShouldBe
  )
where

import           Test.Hspec

import           FreeC.IR.Similar
import           FreeC.Pretty

-------------------------------------------------------------------------------
-- Similarity test                                                           --
-------------------------------------------------------------------------------

-- | Sets the expectation that the given AST nodes are 'similar'.
shouldBeSimilarTo :: (Similar a, Pretty a) => a -> a -> Expectation
shouldBeSimilarTo n m
  | n `similar` m
  = return ()
  | otherwise
  = expectationFailure
    $    showPretty
    $    prettyString "Expected similar nodes, but"
    <$$> line
    <>   indent 2 (pretty n)
    <>   line
    <$$> prettyString "is not similar to"
    <$$> line
    <>   indent 2 (pretty m)
    <>   line

-- | Sets the expectation that the given AST nodes are 'notSimilar'.
shouldNotBeSimilarTo :: (Similar a, Pretty a) => a -> a -> Expectation
shouldNotBeSimilarTo n m
  | n `notSimilar` m
  = return ()
  | otherwise
  = expectationFailure
    $    showPretty
    $    prettyString "Expected dissimilar nodes, but"
    <$$> line
    <>   indent 2 (pretty n)
    <>   line
    <$$> prettyString "is similar to"
    <$$> line
    <>   indent 2 (pretty m)
    <>   line

-------------------------------------------------------------------------------
-- Pretty printing comparison                                                --
-------------------------------------------------------------------------------

-- | Pretty prints both values and tests whether the resulting strings are
--   equal modulo white space.
prettyShouldBe :: (Pretty a, Pretty b) => a -> b -> Expectation
prettyShouldBe x y =
  let discardWhiteSpace = unwords . words
      prettyX           = discardWhiteSpace (showPretty x)
      prettyY           = discardWhiteSpace (showPretty y)
  in  prettyX `shouldBe` prettyY
