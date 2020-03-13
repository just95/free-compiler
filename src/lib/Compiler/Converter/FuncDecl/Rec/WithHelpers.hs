-- | This module contains functions for converting mutually recursive
--   function declarations by spliting when into one or more recursive helper
--   function whose decreasing argument is not lifted to the @Free@ monad and
--   a non-recursive main function.

module Compiler.Converter.FuncDecl.Rec.WithHelpers
  ( convertRecFuncDeclsWithHelpers
  , convertRecFuncDeclsWithHelpers'
  )
where

import           Control.Monad                  ( mapAndUnzipM )
import           Data.List                      ( delete
                                                , elemIndex
                                                )
import qualified Data.List.NonEmpty            as NonEmpty
import qualified Data.Map.Strict               as Map
import           Data.Maybe                     ( fromJust
                                                , maybeToList
                                                )
import qualified Data.Set                      as Set

import           Compiler.Analysis.RecursionAnalysis
import           Compiler.Converter.Expr
import           Compiler.Converter.FuncDecl.Common
import           Compiler.Converter.FuncDecl.NonRec
import qualified Compiler.Coq.AST              as G
import           Compiler.Environment
import           Compiler.Environment.Entry
import           Compiler.Environment.Fresh
import           Compiler.Environment.Renamer
import           Compiler.Environment.Scope
import qualified Compiler.Haskell.AST          as HS
import           Compiler.Haskell.Inliner
import           Compiler.Haskell.SrcSpan
import           Compiler.Haskell.Subterm
import           Compiler.Monad.Converter

-- | Converts recursive function declarations into recursive helper and
--   non-recursive main functions.
convertRecFuncDeclsWithHelpers :: [HS.FuncDecl] -> Converter [G.Sentence]
convertRecFuncDeclsWithHelpers decls = do
  (helperDecls', mainDecls') <- convertRecFuncDeclsWithHelpers' decls
  return
    (  G.comment ("Helper functions for " ++ HS.prettyDeclIdents decls)
    :  helperDecls'
    ++ mainDecls'
    )

-- | Like 'convertRecFuncDeclsWithHelpers' but does return the helper and
--   main functions separtly.
convertRecFuncDeclsWithHelpers'
  :: [HS.FuncDecl] -> Converter ([G.Sentence], [G.Sentence])
convertRecFuncDeclsWithHelpers' decls = do
  -- Split into helper and main functions.
  decArgs                  <- identifyDecArgs decls
  (helperDecls, mainDecls) <- mapAndUnzipM (uncurry transformRecFuncDecl)
                                           (zip decls decArgs)
  -- Convert helper and main functions.
  -- The right hand side of the main functions are inlined into helper the
  -- functions. Because inlining can produce fesh identifiers, we need to
  -- perform inlining and conversion of helper functions in a local environment.
  helperDecls' <- flip mapM (concat helperDecls) $ \helperDecl -> localEnv $ do
    inlinedHelperDecl <- inlineFuncDecls mainDecls helperDecl
    convertRecHelperFuncDecl inlinedHelperDecl
  mainDecls' <- mapM convertNonRecFuncDecl mainDecls

  -- Create common fixpoint sentence for all helper functions.
  return
    ( [G.FixpointSentence (G.Fixpoint (NonEmpty.fromList helperDecls') [])]
    , mainDecls'
    )

-- | Transforms the given recursive function declaration with the specified
--   decreasing argument into recursive helper functions and a non recursive
--   main function.
transformRecFuncDecl
  :: HS.FuncDecl -> DecArgIndex -> Converter ([HS.FuncDecl], HS.FuncDecl)
transformRecFuncDecl (HS.FuncDecl srcSpan declIdent typeArgs args expr maybeRetType) decArgIndex
  = do
  -- Generate a helper function declaration and application for each case
  -- expression of the decreasing argument.
    (helperDecls, helperApps) <- mapAndUnzipM generateHelperDecl caseExprsPos

    -- Generate main function declaration. The main function's right hand side
    -- is constructed by replacing all case expressions of the decreasing
    -- argument by an invocation of the corresponding recursive helper function.
    let (Just mainExpr) = replaceSubterms expr (zip caseExprsPos helperApps)
        mainDecl =
          HS.FuncDecl srcSpan declIdent typeArgs args mainExpr maybeRetType

    -- If the user specified the decreasing argument of the function to
    -- transform, that information needs to be removed since the main function
    -- is not recursive anymore.
    modifyEnv $ removeDecArg name

    return (helperDecls, mainDecl)
 where
  -- | The name of the function to transform.
  name :: HS.QName
  name = HS.UnQual (HS.Ident (HS.fromDeclIdent declIdent))

  -- | The names of the function's arguments.
  argNames :: [HS.QName]
  argNames = map (HS.UnQual . HS.Ident . HS.fromVarPat) args

  -- | The name of the decreasing argument.
  decArg :: HS.QName
  decArg = argNames !! decArgIndex

  -- | The positions of @case@-expressions for the decreasing argument.
  caseExprsPos :: [Pos]
  caseExprsPos = [ p | p <- ps, all (not . below p) (delete p ps) ]
   where
    ps :: [Pos]
    ps = filter decArgNotShadowed (findSubtermPos isCaseExpr expr)

  -- | Tests whether the given expression is a @case@-expression for the
  --   the decreasing argument.
  isCaseExpr :: HS.Expr -> Bool
  isCaseExpr (HS.Case _ (HS.Var _ varName) _) = varName == decArg
  isCaseExpr _ = False

  -- | Ensures that the decreasing argument is not shadowed by the binding
  --   of a local variable at the given position.
  decArgNotShadowed :: Pos -> Bool
  decArgNotShadowed p = decArg `Set.notMember` boundVarsAt expr p

  -- | Generates the recursive helper function declaration for the @case@
  --   expression at the given position of the right hand side.
  --
  --   Returns the helper function declaration and an expression for the
  --   application of the helper function.
  generateHelperDecl :: Pos -> Converter (HS.FuncDecl, HS.Expr)
  generateHelperDecl caseExprPos = do
    -- Generate a fresh name for the helper function.
    helperIdent <- freshHaskellIdent (HS.fromDeclIdent declIdent)
    let helperName      = HS.UnQual (HS.Ident helperIdent)
        helperDeclIdent = HS.DeclIdent (HS.getSrcSpan declIdent) helperIdent

    -- Pass all type arguments to helper function.
    let helperTypeArgs = typeArgs

    -- Pass used variables as additional arguments to the helper function
    -- but don't pass shadowed arguments to helper function.
    let
      nonArgVars     = boundVarsAt expr caseExprPos
      boundVars      = nonArgVars `Set.union` Set.fromList argNames
      usedVars       = usedVarsAt expr caseExprPos
      helperArgNames = Set.toList (usedVars `Set.intersection` boundVars)
      helperArgs =
        map (HS.toVarPat . fromJust . HS.identFromQName) helperArgNames

    -- Register the helper function to the environment.
    -- The types of the original parameters are known, but we neither know the
    -- type of the additional parameters nor the return type of the helper
    -- function.
    -- If the original function was partial, the helper function is partial as
    -- well.
    -- TODO should we just infer the type of the helper functions?
    let maybeArgTypes = map HS.varPatType args
        argTypeMap    = Map.fromList
          [ (argName, argType)
          | argName <- argNames
          , argName `Set.notMember` nonArgVars
          , maybeArgType <- maybeArgTypes
          , argType      <- maybeToList maybeArgType
          ]
        helperArgTypes = map (`Map.lookup` argTypeMap) helperArgNames
    freeArgsNeeded <- inEnv $ needsFreeArgs name
    partial        <- inEnv $ isPartial name
    _              <- renameAndAddEntry $ FuncEntry
      { entrySrcSpan       = NoSrcSpan
      , entryArity         = length helperArgTypes
      , entryTypeArgs      = map HS.fromDeclIdent helperTypeArgs
      , entryArgTypes      = helperArgTypes
      , entryReturnType    = Nothing
      , entryNeedsFreeArgs = freeArgsNeeded
      , entryIsPartial     = partial
      , entryName          = HS.UnQual (HS.Ident helperIdent)
      , entryIdent         = undefined -- filled by renamer
      }

    -- Additionally we need to remember the index of the decreasing argument
    -- (see 'convertArgs').
    let Just decArgIndex' = elemIndex decArg helperArgNames
        Just decArgIdent  = HS.identFromQName decArg
    modifyEnv $ defineDecArg helperName decArgIndex' decArgIdent

    -- Build helper function declaration and application.
    let
      helperTypeArgs' = map HS.typeVarDeclToType helperTypeArgs
      (Just caseExpr) = selectSubterm expr caseExprPos
      helperDecl      = HS.FuncDecl srcSpan
                                    helperDeclIdent
                                    helperTypeArgs
                                    helperArgs
                                    caseExpr
                                    Nothing
      helperApp = HS.app
        NoSrcSpan
        (HS.visibleTypeApp NoSrcSpan
                           (HS.Var NoSrcSpan helperName)
                           helperTypeArgs'
        )
        (map (HS.Var NoSrcSpan) helperArgNames)

    return (helperDecl, helperApp)

-- | Converts a recursive helper function to the body of a Coq @Fixpoint@
--   sentence.
convertRecHelperFuncDecl :: HS.FuncDecl -> Converter G.FixBody
convertRecHelperFuncDecl helperDecl = localEnv $ do
  -- Convert left- and right-hand side of helper function.
  (qualid, binders, returnType') <- convertFuncHead helperDecl
  rhs'                           <- convertExpr (HS.funcDeclRhs helperDecl)
  -- Lookup name of decreasing argument.
  let helperName = HS.UnQual (HS.funcDeclName helperDecl)
      argNames   = map HS.varPatQName (HS.funcDeclArgs helperDecl)
  Just decArgIndex               <- inEnv $ lookupDecArgIndex helperName
  Just decArg' <- inEnv $ lookupIdent ValueScope (argNames !! decArgIndex)
  -- Generate body of @Fixpoint@ sentence.
  return
    (G.FixBody qualid
               (NonEmpty.fromList binders)
               (Just (G.StructOrder decArg'))
               returnType'
               rhs'
    )
