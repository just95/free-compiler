-- | This module contains functions for inlining the definition of
--   functions into expressions or other function declarations.
--
--   This is used during the translation of recursive function declarations
--   to inline the definition of the non-recursive main function into the
--   recursive helper functions.

module Compiler.Haskell.Inliner where

import           Data.Map.Strict                ( Map )
import qualified Data.Map.Strict               as Map

import qualified Compiler.Haskell.AST          as HS
import           Compiler.Haskell.SrcSpan
import           Compiler.Haskell.Subst
import           Compiler.Monad.Converter

-- | Inlines the right hand sides of the given function declarations into
--   the right hand sides of other function declarations.
inlineDecl :: [HS.Decl] -> HS.Decl -> Converter HS.Decl
inlineDecl decls (HS.FuncDecl srcSpan declIdent args expr) = do
  expr' <- inlineExpr decls expr
  return (HS.FuncDecl srcSpan declIdent args expr')
inlineDecl _ decl = return decl

-- | Inlines the right hand sides of the given function declarations into an
--   expression.
inlineExpr :: [HS.Decl] -> HS.Expr -> Converter HS.Expr
inlineExpr decls = inlineAndBind
 where
  -- | Maps the names of function declarations in 'decls' to the arguments
  --   and right hand sides of the functions.
  declMap :: Map HS.Name ([HS.VarPat], HS.Expr)
  declMap = foldr insertFuncDecl Map.empty decls

  -- | Inserts a function declaration into 'declMap'.
  insertFuncDecl
    :: HS.Decl                            -- ^ The declaration to insert.
    -> Map HS.Name ([HS.VarPat], HS.Expr) -- ^ The map to insert into.
    -> Map HS.Name ([HS.VarPat], HS.Expr)
  insertFuncDecl (HS.FuncDecl _ (HS.DeclIdent _ ident) args expr) =
    Map.insert (HS.Ident ident) (args, expr)
  insertFuncDecl _ = id

  -- | Applies 'inlineExpr'' on the given expression and wraps the result with
  --   lambda abstractions for the remaining arguments.
  inlineAndBind :: HS.Expr -> Converter HS.Expr
  inlineAndBind expr = do
    (remainingArgIdents, expr') <- inlineExpr' expr
    if null remainingArgIdents
      then return expr'
      else do
        let remainingArgPats = map (HS.VarPat NoSrcSpan) remainingArgIdents
        return (HS.Lambda NoSrcSpan remainingArgPats expr')

  -- | Performs inlining on the given subexpression.
  --
  --   If a function is inlined, fresh free variables are introduced for the
  --   function arguments. The first component of the returned pair contains
  --   the names of the variables that still need to be bound. Function
  --   application expressions automatically substitute the corresponding
  --   argument for the passed value.
  inlineExpr' :: HS.Expr -> Converter ([String], HS.Expr)
  inlineExpr' var@(HS.Var _ name) = case Map.lookup name declMap of
    Nothing          -> return ([], var)
    Just (args, rhs) -> do
      (args', rhs') <- renameArgs args rhs
      return (map HS.fromVarPat args', rhs')

  -- Substitute argument of inlined function and inline recursively in
  -- function arguments.
  inlineExpr' (HS.App srcSpan e1 e2) = do
    (remainingArgs, e1') <- inlineExpr' e1
    e2'                  <- inlineAndBind e2
    case remainingArgs of
      []                     -> return ([], HS.App srcSpan e1' e2')
      (arg : remainingArgs') -> do
        let subst = singleSubst (HS.Ident arg) e2'
        e1'' <- applySubst subst e1'
        return (remainingArgs', e1'')

  -- Inline recursively.
  inlineExpr' (HS.If srcSpan e1 e2 e3) = do
    e1' <- inlineAndBind e1
    e2' <- inlineAndBind e2
    e3' <- inlineAndBind e3
    return ([], HS.If srcSpan e1' e2' e3')
  inlineExpr' (HS.Case srcSpan expr alts) = do
    expr' <- inlineAndBind expr
    alts' <- mapM inlineAlt alts
    return ([], HS.Case srcSpan expr' alts')
  inlineExpr' (HS.Lambda srcSpan args expr) = do
    expr' <- inlineAndBind expr
    return ([], HS.Lambda srcSpan args expr')

  -- All other expressions remain unchanged.
  inlineExpr' expr@(HS.Con _ _       ) = return ([], expr)
  inlineExpr' expr@(HS.Undefined _   ) = return ([], expr)
  inlineExpr' expr@(HS.ErrorExpr  _ _) = return ([], expr)
  inlineExpr' expr@(HS.IntLiteral _ _) = return ([], expr)

  -- | Performs inlining on the right hand side of the given @case@-expression
  --   alternative.
  inlineAlt :: HS.Alt -> Converter HS.Alt
  inlineAlt (HS.Alt srcSpan conPat varPats expr) = do
    expr' <- inlineAndBind expr
    return (HS.Alt srcSpan conPat varPats expr')