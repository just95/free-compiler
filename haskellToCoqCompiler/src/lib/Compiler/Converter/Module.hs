-- | This module contains functions for converting Haskell modules to Coq.

module Compiler.Converter.Module where

import           Control.Monad.Extra            ( concatMapM )
import           Data.Maybe                     ( maybe )

import           Compiler.Analysis.DependencyAnalysis
import           Compiler.Analysis.DependencyGraph
import           Compiler.Analysis.PartialityAnalysis
import           Compiler.Converter.FuncDecl
import           Compiler.Converter.TypeDecl
import qualified Compiler.Coq.AST              as G
import qualified Compiler.Coq.Base             as CoqBase
import           Compiler.Environment
import qualified Compiler.Haskell.AST          as HS
import           Compiler.Monad.Converter

-------------------------------------------------------------------------------
-- Modules                                                                   --
-------------------------------------------------------------------------------

-- | Converts a Haskell module to a Gallina module sentence and adds
--   import sentences for the Coq Base library that accompanies the compiler.
convertModuleWithPreamble :: HS.Module -> Converter [G.Sentence]
convertModuleWithPreamble ast = do
  coqAst <- convertModule ast
  return [CoqBase.imports, coqAst]

-- | Converts a Haskell module to a Gallina module sentence.
--
--   If no module header is present the generated module is called @"Main"@.
convertModule :: HS.Module -> Converter G.Sentence
convertModule (HS.Module _ maybeIdent decls) = do
  let modName = G.ident (maybe "Main" id maybeIdent)
  decls' <- convertDecls decls
  return (G.LocalModuleSentence (G.LocalModule modName decls'))

-------------------------------------------------------------------------------
-- Declarations                                                              --
-------------------------------------------------------------------------------

-- | Converts the declarations from a Haskell module to Coq.
convertDecls :: [HS.Decl] -> Converter [G.Sentence]
convertDecls decls = do
  typeDecls' <- concatMapM convertTypeComponent (groupDependencies typeGraph)
  mapM_ (modifyEnv . definePartial) (partialFunctions funcGraph)
  mapM_ filterAndDefineTypeSig      decls
  funcDecls' <- concatMapM convertFuncComponent (groupDependencies funcGraph)
  return (typeDecls' ++ funcDecls')
 where
  typeGraph, funcGraph :: DependencyGraph
  typeGraph = typeDependencyGraph decls
  funcGraph = funcDependencyGraph decls

-------------------------------------------------------------------------------
-- Type signatures                                                           --
-------------------------------------------------------------------------------

-- | Inserts the given type signature into the current environment.
--
--   TODO error if there are multiple type signatures for the same function.
--   TODO warn if there are unused type signatures.
filterAndDefineTypeSig :: HS.Decl -> Converter ()
filterAndDefineTypeSig (HS.TypeSig _ idents typeExpr) = do
  mapM_
    (modifyEnv . flip defineTypeSig typeExpr . HS.Ident . HS.fromDeclIdent)
    idents
filterAndDefineTypeSig _ = return () -- ignore other declarations.