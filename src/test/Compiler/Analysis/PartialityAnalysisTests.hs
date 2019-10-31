module Compiler.Analysis.PartialityAnalysisTests where

import           Test.Hspec

import           Compiler.Environment
import qualified Compiler.Haskell.AST          as HS
import           Compiler.Monad.Converter

import           Compiler.Util.Test

-- | Test group for 'identifyPartialFuncs' tests.
testPartialityAnalysis :: Spec
testPartialityAnalysis = describe "Compiler.Analysis.PartialityAnalysis" $ do
  it "recognizes directly partial functions using 'undefined'"
    $ shouldSucceed
    $ fromConverter
    $ do
        _ <- convertTestDecls
          [ "head :: [a] -> a"
          , "head xs = case xs of { [] -> undefined; x : xs' -> x }"
          ]
        partial <- inEnv $ isPartial (HS.Ident "head")
        return (partial `shouldBe` True)

  it "recognizes directly partial functions using 'error'"
    $ shouldSucceed
    $ fromConverter
    $ do
        _ <- convertTestDecls
          [ "head :: [a] -> a"
          , "head xs = case xs of {"
          ++ "  []      -> error \"head: empty list\";"
          ++ "  x : xs' -> x"
          ++ "}"
          ]
        partial <- inEnv $ isPartial (HS.Ident "head")
        return (partial `shouldBe` True)

  it "recognizes indirectly partial functions"
    $ shouldSucceed
    $ fromConverter
    $ do
        _       <- defineTestFunc "map" 2 "(a -> b) -> [a] -> [b]"
        _       <- definePartialTestFunc "head" 1 "[a] -> a"
        _ <- convertTestDecls ["heads :: [[a]] -> [a]", "heads = map head"]
        partial <- inEnv $ isPartial (HS.Ident "heads")
        return (partial `shouldBe` True)
