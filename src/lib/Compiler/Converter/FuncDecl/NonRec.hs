-- | This module contains a function for converting non-recursive
--   Haskell functions to Coq.

module Compiler.Converter.FuncDecl.NonRec
  ( convertNonRecFuncDecl
  )
where

import qualified Compiler.Backend.Coq.Syntax   as G
import           Compiler.Converter.Expr
import           Compiler.Converter.FuncDecl.Common
import qualified Compiler.IR.Syntax            as HS
import           Compiler.Monad.Converter

-- | Converts a non-recursive Haskell function declaration to a Coq
--   @Definition@ sentence.
convertNonRecFuncDecl :: HS.FuncDecl -> Converter G.Sentence
convertNonRecFuncDecl funcDecl = localEnv $ do
  (qualid, binders, returnType') <- convertFuncHead funcDecl
  rhs'                           <- convertExpr (HS.funcDeclRhs funcDecl)
  return (G.definitionSentence qualid binders returnType' rhs')
