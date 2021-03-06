-- | This module contains functions to lookup entries of the 'Environment'
--   that (in contrast to the functions defined in "FreeC.Environment")
--   report a fatal error message when there is no such entry.

module FreeC.Environment.LookupOrFail where

import qualified FreeC.Backend.Coq.Syntax      as Coq
import           FreeC.Environment
import           FreeC.Environment.Entry
import           FreeC.IR.SrcSpan
import qualified FreeC.IR.Syntax               as IR
import           FreeC.Monad.Converter
import           FreeC.Monad.Reporter
import           FreeC.Pretty

-- | Looks up an entry of the environment with the given name or reports
--   a fatal error message if the identifier has not been defined or the
--   name is ambigious.
--
--   If an error is reported, it points to the given source span.
lookupEntryOrFail :: SrcSpan -> IR.Scope -> IR.QName -> Converter EnvEntry
lookupEntryOrFail srcSpan scope name = do
  maybeEntry <- inEnv $ lookupEntry scope name
  case maybeEntry of
    Just entry -> return entry
    Nothing ->
      reportFatal
        $  Message srcSpan Error
        $  "Identifier not in scope '"
        ++ showPretty name
        ++ "'"

-- | Looks up the Coq identifier for a Haskell function, (type)
--   constructor or (type) variable with the given name or reports a fatal
--   error message if the identifier has not been defined.
--
--   If an error is reported, it points to the given source span.
lookupIdentOrFail
  :: SrcSpan  -- ^ The source location where the identifier is requested.
  -> IR.Scope    -- ^ The scope to look the identifier up in.
  -> IR.QName -- ^ The Haskell identifier to look up.
  -> Converter Coq.Qualid
lookupIdentOrFail srcSpan scope name = do
  entry <- lookupEntryOrFail srcSpan scope name
  return (entryIdent entry)

-- | Looks up the Coq identifier of a smart constructor of the Haskell
--   data constructr with the given name or reports a fatal error message
--   if there is no such constructor.
--
--   If an error is reported, it points to the given source span.
lookupSmartIdentOrFail
  :: SrcSpan  -- ^ The source location where the identifier is requested.
  -> IR.QName -- ^ The Haskell identifier to look up.
  -> Converter Coq.Qualid
lookupSmartIdentOrFail srcSpan name = do
  entry <- lookupEntryOrFail srcSpan IR.ValueScope name
  return (entrySmartIdent entry)
