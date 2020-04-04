-- | This module contains functions for converting type synonym and data type
--   declarations and their constructors.

module FreeC.Backend.Coq.Converter.TypeDecl where

import           Control.Monad                  ( mapAndUnzipM )
import           Control.Monad.Extra            ( concatMapM )
import           Data.List                      ( partition )
import qualified Data.List.NonEmpty            as NonEmpty
import           Data.Maybe                     ( catMaybes )
import qualified Data.Set                      as Set

import qualified FreeC.Backend.Coq.Syntax      as G
import           FreeC.Backend.Coq.Converter.Arg
import           FreeC.Backend.Coq.Converter.Free
import           FreeC.Backend.Coq.Converter.Type
import qualified FreeC.Backend.Coq.Base        as CoqBase
import           FreeC.Environment
import           FreeC.Environment.Scope
import           FreeC.IR.DependencyGraph
import qualified FreeC.IR.Syntax               as HS
import           FreeC.IR.TypeSynExpansion
import           FreeC.Monad.Converter
import           FreeC.Monad.Reporter
import           FreeC.Pretty

-------------------------------------------------------------------------------
-- Strongly connected components                                             --
-------------------------------------------------------------------------------

-- | Converts a strongly connected component of the type dependency graph.
convertTypeComponent
  :: DependencyComponent HS.TypeDecl -> Converter [G.Sentence]
convertTypeComponent (NonRecursive decl)
  | isTypeSynDecl decl = convertTypeSynDecl decl
  | otherwise          = convertDataDecls [decl]
convertTypeComponent (Recursive decls) = do
  let (typeSynDecls, dataDecls) = partition isTypeSynDecl decls
      typeSynDeclQNames = Set.fromList (map HS.typeDeclQName typeSynDecls)
  sortedTypeSynDecls <- sortTypeSynDecls typeSynDecls
  expandedDataDecls  <- mapM
    (expandAllTypeSynonymsInDeclWhere (`Set.member` typeSynDeclQNames))
    dataDecls
  dataDecls'    <- convertDataDecls expandedDataDecls
  typeSynDecls' <- concatMapM convertTypeSynDecl sortedTypeSynDecls
  return (dataDecls' ++ typeSynDecls')

-- | Sorts type synonym declarations topologically.
--
--   After filtering type synonym declarations from the a strongly connected
--   component, they are not mutually dependent on each other anymore (expect
--   if they form a cycle). However, type synonyms may still depend on other
--   type synonyms from the same strongly connected component. Therefore we
--   have to sort the declarations in reverse topological order.
sortTypeSynDecls :: [HS.TypeDecl] -> Converter [HS.TypeDecl]
sortTypeSynDecls = mapM fromNonRecursive . groupTypeDecls

-- | Extracts the single type synonym declaration from a strongly connected
--   component of the type dependency graph.
--
--   Reports a fatal error if the component contains mutually recursive
--   declarations (i.e. type synonyms form a cycle).
fromNonRecursive :: DependencyComponent HS.TypeDecl -> Converter HS.TypeDecl
fromNonRecursive (NonRecursive decl) = return decl
fromNonRecursive (Recursive decls) =
  reportFatal
    $  Message (HS.typeDeclSrcSpan (head decls)) Error
    $  "Type synonym declarations form a cycle: "
    ++ showPretty (map HS.typeDeclIdent decls)

-------------------------------------------------------------------------------
-- Type synonym declarations                                                 --
-------------------------------------------------------------------------------

-- | Tests whether the given declaration is a type synonym declaration.
isTypeSynDecl :: HS.TypeDecl -> Bool
isTypeSynDecl (HS.TypeSynDecl _ _ _ _) = True
isTypeSynDecl (HS.DataDecl    _ _ _ _) = False

-- | Converts a Haskell type synonym declaration to Coq.
convertTypeSynDecl :: HS.TypeDecl -> Converter [G.Sentence]
convertTypeSynDecl decl@(HS.TypeSynDecl _ _ typeVarDecls typeExpr) =
  localEnv $ do
    let name = HS.typeDeclQName decl
    Just qualid   <- inEnv $ lookupIdent TypeScope name
    typeVarDecls' <- convertTypeVarDecls G.Explicit typeVarDecls
    typeExpr'     <- convertType' typeExpr
    return
      [ G.definitionSentence qualid
                             (genericArgDecls G.Explicit ++ typeVarDecls')
                             (Just G.sortType)
                             typeExpr'
      ]

-- Data type declarations are not allowed in this function.
convertTypeSynDecl (HS.DataDecl _ _ _ _) =
  error "convertTypeSynDecl: Data type declaration not allowed."

-------------------------------------------------------------------------------
-- Data type declarations                                                    --
-------------------------------------------------------------------------------

-- | Converts multiple (mutually recursive) Haskell data type declaration
--   declarations.
--
--   Before the declarations are actually translated, their identifiers are
--   inserted into the current environment. Otherwise the data types would
--   not be able to depend on each other. The identifiers for the constructors
--   are inserted into the current environment as well. This makes the
--   constructors more likely to keep their original name if there is a type
--   variable with the same (lowercase) name.
--
--   After the @Inductive@ sentences for the data type declarations there
--   is one @Arguments@ sentence and one smart constructor declaration for
--   each constructor declaration of the given data types.
convertDataDecls :: [HS.TypeDecl] -> Converter [G.Sentence]
convertDataDecls dataDecls = do
  (indBodies, extraSentences) <- mapAndUnzipM convertDataDecl dataDecls
  return
    ( G.comment
        (  "Data type declarations for "
        ++ showPretty (map HS.typeDeclName dataDecls)
        )
    : G.InductiveSentence (G.Inductive (NonEmpty.fromList indBodies) [])
    : concat extraSentences
    )

-- | Converts a Haskell data type declaration to the body of a Coq @Inductive@
--   sentence, the @Arguments@ sentences for it's constructors and the smart
--   constructor declarations.
--
--   Type variables declared by the data type or the smart constructors are
--   not visible outside of this function.
convertDataDecl :: HS.TypeDecl -> Converter (G.IndBody, [G.Sentence])
convertDataDecl (HS.DataDecl _ (HS.DeclIdent _ name) typeVarDecls conDecls) =
  do
    (body, argumentsSentences) <- generateBodyAndArguments
    smartConDecls              <- mapM generateSmartConDecl conDecls
    return
      ( body
      , G.comment ("Arguments sentences for " ++ showPretty (HS.toUnQual name))
      :  argumentsSentences
      ++ G.comment ("Smart constructors for " ++ showPretty (HS.toUnQual name))
      :  smartConDecls
      )
 where
  -- | Generates the body of the @Inductive@ sentence and the @Arguments@
  --   sentences for the constructors but not the smart the smart constructors
  --   of the data type.
  --
  --   Type variables declared by the data type declaration are visible to the
  --   constructor declarations and @Arguments@ sentences created by this
  --   function, but not outside this function. This allows the smart
  --   constructors to reuse the identifiers for their type arguments (see
  --   'generateSmartConDecl').
  generateBodyAndArguments :: Converter (G.IndBody, [G.Sentence])
  generateBodyAndArguments = localEnv $ do
    Just qualid        <- inEnv $ lookupIdent TypeScope name
    typeVarDecls'      <- convertTypeVarDecls G.Explicit typeVarDecls
    conDecls'          <- mapM convertConDecl conDecls
    argumentsSentences <- mapM generateArgumentsSentence conDecls
    return
      ( G.IndBody qualid
                  (genericArgDecls G.Explicit ++ typeVarDecls')
                  G.sortType
                  conDecls'
      , argumentsSentences
      )

  -- | Converts a constructor of the data type.
  convertConDecl :: HS.ConDecl -> Converter (G.Qualid, [G.Binder], Maybe G.Term)
  convertConDecl (HS.ConDecl _ (HS.DeclIdent _ conName) args) = do
    Just conQualid  <- inEnv $ lookupIdent ValueScope conName
    Just returnType <- inEnv $ lookupReturnType ValueScope conName
    args'           <- mapM convertType args
    returnType'     <- convertType' returnType
    return (conQualid, [], Just (args' `G.arrows` returnType'))

  -- | Generates the @Arguments@ sentence for the given constructor declaration.
  generateArgumentsSentence :: HS.ConDecl -> Converter G.Sentence
  generateArgumentsSentence (HS.ConDecl _ (HS.DeclIdent _ conName) _) = do
    Just qualid <- inEnv $ lookupIdent ValueScope conName
    let typeVarNames = map HS.typeVarDeclQName typeVarDecls
    typeVarQualids <- mapM (inEnv . lookupIdent TypeScope) typeVarNames
    return
      (G.ArgumentsSentence
        (G.Arguments
          Nothing
          qualid
          [ G.ArgumentSpec G.ArgMaximal (G.Ident typeVarQualid) Nothing
          | typeVarQualid <- map fst CoqBase.freeArgs
            ++ catMaybes typeVarQualids
          ]
        )
      )

  -- | Generates the smart constructor declaration for the given constructor
  --   declaration.
  generateSmartConDecl :: HS.ConDecl -> Converter G.Sentence
  generateSmartConDecl (HS.ConDecl _ declIdent argTypes) = localEnv $ do
    let conName = HS.declIdentName declIdent
    Just qualid             <- inEnv $ lookupIdent ValueScope conName
    Just smartQualid        <- inEnv $ lookupSmartIdent conName
    Just returnType         <- inEnv $ lookupReturnType ValueScope conName
    typeVarDecls'           <- convertTypeVarDecls G.Implicit typeVarDecls
    (argIdents', argDecls') <- mapAndUnzipM convertAnonymousArg
                                            (map Just argTypes)
    returnType' <- convertType returnType
    rhs <- generatePure (G.app (G.Qualid qualid) (map G.Qualid argIdents'))
    return
      (G.definitionSentence
        smartQualid
        (genericArgDecls G.Explicit ++ typeVarDecls' ++ argDecls')
        (Just returnType')
        rhs
      )

-- Type synonyms are not allowed in this function.
convertDataDecl (HS.TypeSynDecl _ _ _ _) =
  error "convertDataDecl: Type synonym not allowed."