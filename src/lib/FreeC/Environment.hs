-- | This module contains a data type that encapsulates the state of
--   the compiler. There are also utility functions to modify the state and
--   retrieve information stored in the state.

module FreeC.Environment
  ( -- * Environment
    Environment(..)
  , emptyEnv
  -- * Module information
  , makeModuleAvailable
  , isModuleAvailable
  , lookupAvailableModule
  -- * Inserting entries into the environment
  , addEntry
  , defineDecArg
  , removeDecArg
  -- * Looking up entries from the environment
  , lookupEntry
  , isFunction
  , isVariable
  , isPureVar
  , lookupIdent
  , lookupSmartIdent
  , usedIdents
  , lookupSrcSpan
  , lookupTypeArgs
  , lookupTypeArgArity
  , lookupArgTypes
  , lookupReturnType
  , lookupTypeSchema
  , lookupArity
  , lookupTypeSynonym
  , needsFreeArgs
  , isPartial
  , lookupDecArg
  , lookupDecArgIndex
  , lookupDecArgIdent
  )
where

import           Data.Composition               ( (.:)
                                                , (.:.)
                                                )
import           Data.List                      ( find )
import           Data.Map.Strict                ( Map )
import qualified Data.Map.Strict               as Map
import           Data.Maybe                     ( catMaybes
                                                , isJust
                                                )
import           Data.Tuple.Extra               ( (&&&) )

import qualified FreeC.Backend.Coq.Syntax      as Coq
import           FreeC.Environment.Entry
import           FreeC.Environment.ModuleInterface
import qualified FreeC.IR.Syntax               as IR
import           FreeC.IR.SrcSpan
import           FreeC.Util.Predicate

-------------------------------------------------------------------------------
-- Environment                                                               --
-------------------------------------------------------------------------------

-- | Data type that encapsulates the state of the converter.
data Environment = Environment
  { envAvailableModules  :: Map IR.ModName ModuleInterface
    -- ^ Maps names of modules that can be imported to their interface.

  , envEntries           :: Map IR.ScopedName EnvEntry
    -- ^ Maps original names of entries for declarations to the entries.
  , envDecArgs           :: Map IR.QName (Int, String)
    -- ^ Maps Haskell function names to the index and name of their decreasing
    --   argument. Contains no entry for non-recursive functions, but there are
    --   also entries for functions that are shadowed by local variables.
  , envFreshIdentCount   :: Map String Int
    -- ^ The number of fresh identifiers that were used in the environment
    --   with a certain prefix.
  }
 deriving Show

-- | An environment that does not even contain any predefined types and
--   functions.
emptyEnv :: Environment
emptyEnv = Environment { -- Modules
                         envAvailableModules = Map.empty
                         -- Entries
                       , envEntries          = Map.empty
                       , envDecArgs          = Map.empty
                       , envFreshIdentCount  = Map.empty
                       }

-------------------------------------------------------------------------------
-- Modules                                                                   --
-------------------------------------------------------------------------------

-- | Inserts the interface of a module name into the environment such that it
--   can be imported.
makeModuleAvailable :: ModuleInterface -> Environment -> Environment
makeModuleAvailable iface env = env
  { envAvailableModules = Map.insert (interfaceModName iface)
                                     iface
                                     (envAvailableModules env)
  }

-- | Tests whether the module with the given name can be imported.
isModuleAvailable :: IR.ModName -> Environment -> Bool
isModuleAvailable = isJust .: lookupAvailableModule

-- | Looks up the environment of another module that can be imported.
lookupAvailableModule :: IR.ModName -> Environment -> Maybe ModuleInterface
lookupAvailableModule modName = Map.lookup modName . envAvailableModules

-------------------------------------------------------------------------------
-- Inserting entries into the environment                                    --
-------------------------------------------------------------------------------

-- | Inserts an entry into the given environment and associates it with
--   its original name.
addEntry :: EnvEntry -> Environment -> Environment
addEntry entry env =
  env { envEntries = Map.insert (entryScopedName entry) entry (envEntries env) }

-- | Stores the index and name of the decreasing argument of a recursive
--   function in the environment.
defineDecArg :: IR.QName -> Int -> String -> Environment -> Environment
defineDecArg funcName decArgIndex decArgIdent env = env
  { envDecArgs = Map.insert funcName (decArgIndex, decArgIdent) (envDecArgs env)
  }

-- | Removes the index of the decreasing argument of a recursive function
--   from the environment (e.g., because the function has been transformed
--   into a non-recursive function).
removeDecArg :: IR.QName -> Environment -> Environment
removeDecArg funcName env =
  env { envDecArgs = Map.delete funcName (envDecArgs env) }

-------------------------------------------------------------------------------
-- Looking up entries from the environment                                   --
-------------------------------------------------------------------------------

-- | Looks up the entry with the given original name in the given scope of
--   the given environment.
lookupEntry :: IR.Scope -> IR.QName -> Environment -> Maybe EnvEntry
lookupEntry scope name = Map.lookup (scope, name) . envEntries

-- | Tests whether the given name identifies a function in the given
--   environment.
--
--   Returns @False@ if there is no such function.
isFunction :: IR.QName -> Environment -> Bool
isFunction = maybe False isFuncEntry .: lookupEntry IR.ValueScope

-- | Tests whether the given name identifies a local variable in the given
--   environment.
--
--   Returns @False@ if there is no such variable.
isVariable :: IR.QName -> Environment -> Bool
isVariable = maybe False isVarEntry .: lookupEntry IR.ValueScope

-- | Test whether the variable with the given name is not monadic.
isPureVar :: IR.QName -> Environment -> Bool
isPureVar =
  maybe False (isVarEntry .&&. entryIsPure) .: lookupEntry IR.ValueScope

-- | Looks up the Coq identifier for a Haskell function, (type)
--   constructor or (type) variable with the given name.
--
--   Returns @Nothing@ if there is no such function, (type/smart) constructor,
--   constructor or (type) variable with the given name.
lookupIdent :: IR.Scope -> IR.QName -> Environment -> Maybe Coq.Qualid
lookupIdent = fmap entryIdent .:. lookupEntry

-- | Looks up the Coq identifier for the smart constructor of the Haskell
--   constructor with the given name.
--
--   Returns @Nothing@ if there is no such constructor.
lookupSmartIdent :: IR.QName -> Environment -> Maybe Coq.Qualid
lookupSmartIdent =
  fmap entrySmartIdent . find isConEntry .: lookupEntry IR.ValueScope

-- | Gets a list of Coq identifiers for functions, (type/smart) constructors,
--   (type/fresh) variables that were used in the given environment already.
usedIdents :: Environment -> [Coq.Qualid]
usedIdents = concatMap entryIdents . Map.elems . envEntries
 where
  entryIdents :: EnvEntry -> [Coq.Qualid]
  entryIdents entry
    | isConEntry entry = [entryIdent entry, entrySmartIdent entry]
    | otherwise        = [entryIdent entry]

-- | Looks up the location of the declaration with the given name.
lookupSrcSpan :: IR.Scope -> IR.QName -> Environment -> Maybe SrcSpan
lookupSrcSpan = fmap entrySrcSpan .:. lookupEntry

-- | Looks up the type variables used by the type synonym, (smart)
--   constructor or type signature of the function with the given name.
--
--   Returns @Nothing@ if there is no such type synonym, function or (smart)
--   constructor with the given name.
lookupTypeArgs :: IR.Scope -> IR.QName -> Environment -> Maybe [IR.TypeVarIdent]
lookupTypeArgs =
  fmap entryTypeArgs
    .   find (isTypeSynEntry .||. isConEntry .||. isFuncEntry)
    .:. lookupEntry

-- | Returns the length of the list returned by @lookupTypeArgs@.
lookupTypeArgArity :: IR.Scope -> IR.QName -> Environment -> Maybe Int
lookupTypeArgArity = fmap length .:. lookupTypeArgs

-- | Looks up the argument and return types of the function or (smart)
--   constructor with the given name.
--
--   Returns @Nothing@ if there is no such function or (smart) constructor
--   with the given name.
lookupArgTypes :: IR.Scope -> IR.QName -> Environment -> Maybe [Maybe IR.Type]
lookupArgTypes =
  fmap entryArgTypes . find (isConEntry .||. isFuncEntry) .:. lookupEntry

-- | Looks up the return type of the function or (smart) constructor with the
--   given name.
--
--   Returns @Nothing@ if there is no such function or (smart) constructor
--   with the given name or the return type is not known.
lookupReturnType :: IR.Scope -> IR.QName -> Environment -> Maybe IR.Type
lookupReturnType =
  (entryReturnType =<<) . find (isConEntry .||. isFuncEntry) .:. lookupEntry

-- | Gets the type schema of the variable, function or constructor with the
--   given name.
lookupTypeSchema :: IR.Scope -> IR.QName -> Environment -> Maybe IR.TypeSchema
lookupTypeSchema scope name env
  | scope == IR.ValueScope && isVariable name env = do
    typeExpr <- lookupEntry scope name env >>= entryType
    return (IR.TypeSchema NoSrcSpan [] typeExpr)
  | otherwise = do
    typeArgs   <- lookupTypeArgs scope name env
    argTypes   <- lookupArgTypes scope name env
    returnType <- lookupReturnType scope name env
    let typeArgDecls = map (IR.TypeVarDecl NoSrcSpan) typeArgs
        funcType     = IR.funcType NoSrcSpan (catMaybes argTypes) returnType
    return (IR.TypeSchema NoSrcSpan typeArgDecls funcType)

-- | Looks up the number of arguments expected by the Haskell function
--   or smart constructor with the given name.
--
--   Returns @Nothing@ if there is no such function or (smart) constructor
--   with the given name.
lookupArity :: IR.Scope -> IR.QName -> Environment -> Maybe Int
lookupArity =
  fmap entryArity
    .   find (not . (isVarEntry .||. isTypeVarEntry))
    .:. lookupEntry

-- | Looks up the type the type synonym with the given name is associated with.
--
--   Returns @Nothing@ if there is no such type synonym.
lookupTypeSynonym
  :: IR.QName -> Environment -> Maybe ([IR.TypeVarIdent], IR.Type)
lookupTypeSynonym =
  fmap (entryTypeArgs &&& entryTypeSyn)
    .  find isTypeSynEntry
    .: lookupEntry IR.TypeScope

-- | Tests whether the function with the given name needs the arguments
--   of the @Free@ monad.
--
--   Returns @False@ if there is no such function.
needsFreeArgs :: IR.QName -> Environment -> Bool
needsFreeArgs =
  maybe False (isFuncEntry .&&. entryNeedsFreeArgs) .: lookupEntry IR.ValueScope

-- | Tests whether the function with the given name is partial.
--
--   Returns @False@ if there is no such function.
isPartial :: IR.QName -> Environment -> Bool
isPartial =
  maybe False (isFuncEntry .&&. entryIsPartial) .: lookupEntry IR.ValueScope

-- | Looks up the index and name of the decreasing argument of the recursive
--   function with the given name.
--
--   Returns @Nothing@ if there is no such recursive function.
lookupDecArg :: IR.QName -> Environment -> Maybe (Int, String)
lookupDecArg name = Map.lookup name . envDecArgs

-- | Like 'lookupDecArg' but returns the decreasing argument's index only.
lookupDecArgIndex :: IR.QName -> Environment -> Maybe Int
lookupDecArgIndex = fmap fst .: lookupDecArg

-- | Like 'lookupDecArg' but returns the decreasing argument's name only.
lookupDecArgIdent :: IR.QName -> Environment -> Maybe String
lookupDecArgIdent = fmap snd .: lookupDecArg
