-- | This module contains tests for "FreeC.Backend.Coq.Converter.Expr".

module FreeC.Backend.Coq.Converter.ExprTests
  ( testConvertExpr
  )
where

import           Test.Hspec

import           FreeC.Backend.Coq.Converter.Expr
import           FreeC.Backend.Coq.Pretty       ( )
import           FreeC.Monad.Class.Testable
import           FreeC.Monad.Converter
import           FreeC.Test.Parser
import           FreeC.Test.Environment
import           FreeC.Test.Expectations

-------------------------------------------------------------------------------
-- Expectation setters                                                       --
-------------------------------------------------------------------------------

-- | Parses the given IR expression, converts it to Coq using 'convertExpr'
--   and sets the expectation that the resulting AST is equal to the given
--   output when pretty printed modulo white space.
shouldConvertExprTo :: String -> String -> Converter Expectation
shouldConvertExprTo inputStr expectedOutputStr = do
  input  <- parseTestExpr inputStr
  output <- convertExpr input
  return (output `prettyShouldBe` expectedOutputStr)

-------------------------------------------------------------------------------
-- Expressions                                                               --
-------------------------------------------------------------------------------

-- | Test group for 'convertExpr' tests.
testConvertExpr :: Spec
testConvertExpr = describe "FreeC.Backend.Coq.Converter.Expr.convertExpr" $ do
  testConvertConApp
  testConvertFuncApp
  testConvertIf
  testConvertCase
  testConvertLambda
  testConvertExprTypeAnnotations
  testConvertTypeAppExprs
  testConvertInteger

-------------------------------------------------------------------------------
-- Constructor applications                                                  --
-------------------------------------------------------------------------------

-- | Test group for translation of constructor application expressions.
testConvertConApp :: Spec
testConvertConApp = context "constructor applications" $ do
  it "converts 0-ary constructor applications correctly"
    $ shouldSucceedWith
    $ do
        "D"        <- defineTestTypeCon "D" 0
        ("c", "C") <- defineTestCon "C" 0 "D"
        "C" `shouldConvertExprTo` "C Shape Pos"

  it "converts polymorphic 0-ary constructor applications correctly"
    $ shouldSucceedWith
    $ do
        "D"        <- defineTestTypeCon "D" 1
        ("c", "C") <- defineTestCon "C" 0 "forall a. D a"
        "a"        <- defineTestTypeVar "a"
        "C @a" `shouldConvertExprTo` "@C Shape Pos a"

  it "converts constructor applications correctly" $ shouldSucceedWith $ do
    "D"      <- defineTestTypeCon "D" 0
    (_, "C") <- defineTestCon "C" 3 "forall a b. a -> b -> D"
    "a"      <- defineTestTypeVar "a"
    "b"      <- defineTestTypeVar "b"
    "x"      <- defineTestVar "x"
    "y"      <- defineTestVar "y"
    "C @a @b x y" `shouldConvertExprTo` "@C Shape Pos a b x y"

  it "converts partial constructor applications correctly"
    $ shouldSucceedWith
    $ do
        "D"      <- defineTestTypeCon "D" 0
        (_, "C") <- defineTestCon "C" 3 "forall a b. a -> b -> D"
        "a"      <- defineTestTypeVar "a"
        "b"      <- defineTestTypeVar "b"
        "x"      <- defineTestVar "x"
        "C @a @b x" `shouldConvertExprTo` "@C Shape Pos a b x"

  it "converts unapplied constructors correctly" $ shouldSucceedWith $ do
    "D"      <- defineTestTypeCon "D" 0
    (_, "C") <- defineTestCon "C" 3 "forall a b. a -> b -> D"
    "a"      <- defineTestTypeVar "a"
    "b"      <- defineTestTypeVar "b"
    "C @a @b" `shouldConvertExprTo` "@C Shape Pos a b"

  it "requires visible type applications of constructors" $ do
    input <- expectParseTestExpr "C"
    shouldFail $ do
      "D"      <- defineTestTypeCon "D" 0
      (_, "C") <- defineTestCon "C" 3 "forall a. a -> D"
      convertExpr input

-------------------------------------------------------------------------------
-- Function applications                                                     --
-------------------------------------------------------------------------------

-- | Test group for translation of function application expressions.
testConvertFuncApp :: Spec
testConvertFuncApp = context "function applications" $ do
  it "converts 0-ary function (pattern-binding) applications correctly"
    $ shouldSucceedWith
    $ do
        "f" <- defineTestFunc "f" 0 "forall a. a"
        "a" <- defineTestTypeVar "a"
        "f @a" `shouldConvertExprTo` "@f Shape Pos a"

  it "converts complete function applications correctly"
    $ shouldSucceedWith
    $ do
        "f" <- defineTestFunc "f" 3 "forall a. a -> a -> a"
        "a" <- defineTestTypeVar "a"
        "x" <- defineTestVar "x"
        "y" <- defineTestVar "y"
        "f @a x y" `shouldConvertExprTo` "@f Shape Pos a x y"

  it "converts partial function applications correctly" $ shouldSucceedWith $ do
    "f" <- defineTestFunc "f" 3 "forall a. a -> a -> a"
    "a" <- defineTestTypeVar "a"
    "x" <- defineTestVar "x"
    "f @a x" `shouldConvertExprTo` "@f Shape Pos a x"

  it "converts unapplied functions correctly" $ shouldSucceedWith $ do
    "f" <- defineTestFunc "f" 3 "forall a. a -> a -> a"
    "a" <- defineTestTypeVar "a"
    "f @a" `shouldConvertExprTo` "@f Shape Pos a"

  it "converts applications of partial functions correctly"
    $ shouldSucceedWith
    $ do
        "f" <- definePartialTestFunc "f" 1 "forall a b. a -> b"
        "a" <- defineTestTypeVar "a"
        "b" <- defineTestTypeVar "b"
        "x" <- defineTestVar "x"
        "f @a @b x" `shouldConvertExprTo` "@f Shape Pos P a b x"

  it "converts applications of function expressions correctly"
    $ shouldSucceedWith
    $ do
        "e1" <- defineTestVar "e1"
        "e2" <- defineTestVar "e2"
        "e1 e2" `shouldConvertExprTo` "e1 >>= (fun e1_0 => e1_0 e2)"

  it "converts applications of functions that return functions correctly"
    $ shouldSucceedWith
    $ do
        "f" <- defineTestFunc "f" 1 "forall a. a -> a -> a"
        "a" <- defineTestTypeVar "a"
        "x" <- defineTestVar "x"
        "y" <- defineTestVar "y"
        shouldConvertExprTo "f @a x y" "@f Shape Pos a x >>= (fun f_0 => f_0 y)"

  it "requires visible type applications of functions" $ do
    input <- expectParseTestExpr "f"
    shouldFail $ do
      "f" <- defineTestFunc "f" 0 "forall a. a"
      convertExpr input

-------------------------------------------------------------------------------
-- If-expressions                                                            --
-------------------------------------------------------------------------------

-- | Test group for translation of @if@-expressions.
testConvertIf :: Spec
testConvertIf = context "if expressions" $ do
  it "converts if expressions correctly" $ shouldSucceedWith $ do
    "Bool" <- defineTestTypeCon "Prelude.Bool" 0
    "e1"   <- defineTestVar "e1"
    "e2"   <- defineTestVar "e2"
    "e3"   <- defineTestVar "e3"
    shouldConvertExprTo "if e1 then e2 else e3"
      $ "e1 >>= (fun (e1_0 : Bool Shape Pos) => if e1_0 then e2 else e3)"

  it "there is no name conflict with custom `Bool`" $ shouldSucceedWith $ do
    "Bool"  <- defineTestTypeCon "M1.Bool" 0
    "Bool0" <- defineTestTypeCon "Prelude.Bool" 0
    "Bool1" <- defineTestTypeCon "M2.Bool" 0
    "e1"    <- defineTestVar "e1"
    "e2"    <- defineTestVar "e2"
    "e3"    <- defineTestVar "e3"
    shouldConvertExprTo "if e1 then e2 else e3"
      $ "e1 >>= (fun (e1_0 : Bool0 Shape Pos) => if e1_0 then e2 else e3)"

-------------------------------------------------------------------------------
-- Case-expressions                                                          --
-------------------------------------------------------------------------------

-- | Test group for translation of @case@-expressions.
testConvertCase :: Spec
testConvertCase = context "case expressions" $ do
  it "simplifies matches with only one alternative (during pretty printing)"
    $ shouldSucceedWith
    $ do
        "e"      <- defineTestVar "e"
        "e'"     <- defineTestVar "e'"
        "D"      <- defineTestTypeCon "D" 0
        ("c", _) <- defineTestCon "C" 0 "D"
        "case e of { C -> e' }" `shouldConvertExprTo` "e >>= (fun '(c) => e')"

  it "uses data (not smart) constructors" $ shouldSucceedWith $ do
    "e"       <- defineTestVar "e"
    "e1"      <- defineTestVar "e1"
    "e2"      <- defineTestVar "e2"
    "D"       <- defineTestTypeCon "D" 0
    ("c1", _) <- defineTestCon "C1" 0 "D"
    ("c2", _) <- defineTestCon "C2" 0 "D"
    shouldConvertExprTo "case e of { C1 -> e1;  C2 -> e2 }"
      $  "e >>= (fun e_0 =>"
      ++ "  match e_0 with"
      ++ "  | c1 => e1"
      ++ "  | c2 => e2"
      ++ "  end)"

  it "allows case expressions to shadow local variables"
    $ shouldSucceedWith
    $ do
        "List"      <- defineTestTypeCon "List" 1
        ("nil" , _) <- defineTestCon "Nil" 0 "forall a. List a"
        ("cons", _) <- defineTestCon "Cons" 2 "forall a. a -> List a -> List a"
        "e"         <- defineTestVar "e"
        "x"         <- defineTestVar "x"
        shouldConvertExprTo "case e of { Nil -> x; Cons x xs -> x }"
          $  "e >>= (fun e_0 =>"
          ++ "  match e_0 with"
          ++ "  | nil => x"
          ++ "  | cons x0 xs => x0"
          ++ "  end)"

-------------------------------------------------------------------------------
-- Lambda abstractions                                                       --
-------------------------------------------------------------------------------

-- | Test group for translation of lambda abstractions.
testConvertLambda :: Spec
testConvertLambda = context "lambda abstractions" $ do
  it "translates single argument lambda abstractions correctly"
    $ shouldSucceedWith
    $ do
        "e" <- defineTestVar "e"
        "\\x -> e" `shouldConvertExprTo` "pure (fun x => e)"

  it "translates lambda abstractions with type annotated arguments correctly"
    $ shouldSucceedWith
    $ do
        "t" <- defineTestTypeVar "t"
        "e" <- defineTestVar "e"
        shouldConvertExprTo "\\(x :: t) -> e"
                            "pure (fun (x : Free Shape Pos t) => e)"

  it "translates multi argument lambda abstractions correctly"
    $ shouldSucceedWith
    $ do
        "e" <- defineTestVar "e"
        "\\x y -> e" `shouldConvertExprTo` "pure (fun x => pure (fun y => e))"

  it "allows lambda abstractions to shadow local variables"
    $ shouldSucceedWith
    $ do
        "x" <- defineTestVar "x"
        "\\x -> x" `shouldConvertExprTo` "pure (fun x0 => x0)"

-------------------------------------------------------------------------------
-- Type signatures                                                           --
-------------------------------------------------------------------------------

-- | Test group for translation of expressions with type annotations.
testConvertExprTypeAnnotations :: Spec
testConvertExprTypeAnnotations = context "type annotations" $ do
  it "ignores expression type annotations" $ shouldSucceedWith $ do
    "42 :: Integer" `shouldConvertExprTo` "pure 42%Z"

-- | Test group for translation of visibly applied expressions.
testConvertTypeAppExprs :: Spec
testConvertTypeAppExprs = context "visible type applications" $ do
  it "translates visible type applications to explicit applications in Coq"
    $ shouldSucceedWith
    $ do
        "Bool"     <- defineTestTypeCon "Bool" 0
        "List"     <- defineTestTypeCon "List" 1
        (_, "Nil") <- defineTestCon "Nil" 0 "forall a. List a"
        "Nil @Bool" `shouldConvertExprTo` "@Nil Shape Pos (Bool Shape Pos)"

-------------------------------------------------------------------------------
-- Integer expressions                                                       --
-------------------------------------------------------------------------------

-- | Test group for translation of integer expressions.
testConvertInteger :: Spec
testConvertInteger = context "integer expressions" $ do
  it "translates zero correctly" $ shouldSucceedWith $ shouldConvertExprTo
    "0"
    "pure 0%Z"

  it "translates positive decimal integer literals correctly"
    $ shouldSucceedWith
    $ shouldConvertExprTo "42" "pure 42%Z"

  it "translates hexadecimal integer literals correctly"
    $ shouldSucceedWith
    $ shouldConvertExprTo "0xA2" "pure 162%Z"

  it "translates octal integer literals correctly"
    $ shouldSucceedWith
    $ shouldConvertExprTo "0o755" "pure 493%Z"

  it "translates negative decimal integer literals correctly"
    $ shouldSucceedWith
    $ shouldConvertExprTo "-42" "pure (- 42)%Z"
