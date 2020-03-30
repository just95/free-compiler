module Compiler.IR.SubtermTests where

import           Test.Hspec
import           Test.QuickCheck

import           Data.Maybe                     ( isJust )
import qualified Data.Set                      as Set

import           Compiler.IR.SrcSpan
import           Compiler.IR.Subterm
import           Compiler.IR.Syntax            as HS

import           Compiler.Util.Test

-------------------------------------------------------------------------------
-- Test data                                                                 --
-------------------------------------------------------------------------------

-- | Creates a generator for valid test positions for the given expression.
validTestPos :: HS.Expr -> Gen Pos
validTestPos expr = oneof (map return (allPos expr))

-- | Creates a generator for invalid test positions for the given expression
--   (i.e. positions that do not identify a subterm of the given expression).
invalidTestPos :: HS.Expr -> Gen Pos
invalidTestPos expr =
  (Pos <$> arbitrary) `suchThat` (not . (`elem` allPos expr))

-- | Creates a generator for test positions for the given expression.
--
--   The @Bool@ indicates whether the position is valid or not.
testPos :: HS.Expr -> Gen (Pos, Bool)
testPos expr = do
  validPos   <- validTestPos expr
  invalidPos <- invalidTestPos expr
  oneof [return (validPos, True), return (invalidPos, False)]

-------------------------------------------------------------------------------
-- Subterm tests                                                             --
-------------------------------------------------------------------------------

-- | Test group for "Compiler.IR.Subterm" tests.
testSubterm :: Spec
testSubterm = describe "Compiler.IR.Subterm" $ do
  beforeAll
      (fromReporter $ fromConverter $ parseTestExpr $ unlines
        [ "\\n xs ->"
        , "  if n < 0"
        , "    then undefined"
        , "    else if n == 0"
        , "      then []"
        , "      else case xs of"
        , "        []      -> []"
        , "        x : xs' -> x : take (n - 1) xs'"
        ]
      )
    $ do
        context "selecting and replacing subterms" $ do
          it "selects valid positions successfully" $ \testExpr ->
            property $ forAll (testPos testExpr) $ \(p, valid) ->
              isJust (selectSubterm testExpr p) == valid

          it "replaces valid positions successfully" $ \testExpr ->
            property $ forAll (testPos testExpr) $ \(p, valid) ->
              let testExpr' =
                      HS.Var NoSrcSpan (HS.UnQual (HS.Ident "x")) Nothing
              in  isJust (replaceSubterm testExpr p testExpr') == valid

          it "produces the input when replacing a subterm with itself"
            $ \testExpr -> property $ forAll (validTestPos testExpr) $ \p ->
                let Just subterm = selectSubterm testExpr p
                in  replaceSubterm testExpr p subterm == Just testExpr

          it "replaces the entire term when replacing at the root position"
            $ \testExpr -> do
                let testExpr' =
                      HS.Var NoSrcSpan (HS.UnQual (HS.Ident "x")) Nothing
                replaceSubterm testExpr rootPos testExpr'
                  `shouldBe` Just testExpr'

        context "searching subterms" $ do
          it "finds subterm positions" $ \testExpr -> do
            let isCase (HS.Case _ _ _ _) = True
                isCase _                 = False
            findSubtermPos isCase testExpr `shouldBe` [Pos [1, 3, 3]]

          it "finds subterms" $ \testExpr -> do
            let isVar (HS.Var _ _ _) = True
                isVar _              = False
            map HS.exprVarName (findSubterms isVar testExpr)
              `shouldBe` [ HS.UnQual (HS.Symbol "<")
                         , HS.UnQual (HS.Ident "n")
                         , HS.UnQual (HS.Symbol "==")
                         , HS.UnQual (HS.Ident "n")
                         , HS.UnQual (HS.Ident "xs")
                         , HS.UnQual (HS.Ident "x")
                         , HS.UnQual (HS.Ident "take")
                         , HS.UnQual (HS.Symbol "-")
                         , HS.UnQual (HS.Ident "n")
                         , HS.UnQual (HS.Ident "xs'")
                         ]

        context "bound variables" $ do
          it "finds no bound variables at root position" $ \testExpr -> do
            boundVarsAt testExpr rootPos `shouldBe` Set.empty

          it "finds bound variables of lambda" $ \testExpr -> do
            boundVarsAt testExpr (Pos [1]) `shouldBe` Set.fromList
              [HS.UnQual (HS.Ident "n"), HS.UnQual (HS.Ident "xs")]

          it "finds bound variables of case alternative" $ \testExpr -> do
            boundVarsAt testExpr (Pos [1, 3, 3, 1]) `shouldBe` Set.fromList
              [HS.UnQual (HS.Ident "n"), HS.UnQual (HS.Ident "xs")]
            boundVarsAt testExpr (Pos [1, 3, 3, 2]) `shouldBe` Set.fromList
              [HS.UnQual (HS.Ident "n"), HS.UnQual (HS.Ident "xs")]
            boundVarsAt testExpr (Pos [1, 3, 3, 3]) `shouldBe` Set.fromList
              [ HS.UnQual (HS.Ident "n")
              , HS.UnQual (HS.Ident "xs")
              , HS.UnQual (HS.Ident "x")
              , HS.UnQual (HS.Ident "xs'")
              ]