{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | This module contains functions for encoding 'ModuleInterface's in JSON
--   and writing them to @.json@ files.
--
--   Encoding module interfaces as TOML files is not supported, since TOML is
--   intended for human maintained configuration files (e.g., the module
--   interface of the @Prelude@) only.
--
--   See "FreeC.Environment.ModuleInterface.Decoder" for more information on
--   the interface file format.

module FreeC.Environment.ModuleInterface.Encoder
  ( writeModuleInterface
  )
where

import           Control.Monad.IO.Class         ( MonadIO )
import           Data.Aeson                     ( (.=) )
import qualified Data.Aeson                    as Aeson
import           Data.Maybe                     ( mapMaybe )
import qualified Data.Set                      as Set

import           FreeC.Backend.Coq.Pretty
import qualified FreeC.Backend.Coq.Syntax      as Coq
import           FreeC.Environment.Entry
import           FreeC.Environment.ModuleInterface
import           FreeC.IR.SrcSpan
import qualified FreeC.IR.Syntax               as IR
import           FreeC.Monad.Reporter
import           FreeC.Pretty
import           FreeC.Util.Config

-- | The version number of the module interface file format.
--
--   Remember to keep this in sync with the version number specified in
--   "FreeC.Environment.ModuleInterface.Decoder".
--
--   We specify the version number at two different places such that if
--   a breaking change is made to the encoder or decoder, it is less likely
--   that the implementation of the corresponding change in the other module
--   is forgotten.
moduleInterfaceFileFormatVersion :: Integer
moduleInterfaceFileFormatVersion = 1

instance Aeson.ToJSON IR.QName where
  toJSON = Aeson.toJSON . showPretty

instance Aeson.ToJSON IR.Type where
  toJSON = Aeson.toJSON . showPretty

instance Aeson.ToJSON Coq.Qualid where
  toJSON = Aeson.toJSON . showPretty . PrettyCoq

-- | Serializes a 'ModuleInterface'.
instance Aeson.ToJSON ModuleInterface where
  toJSON iface = Aeson.object
    [ "version" .= moduleInterfaceFileFormatVersion
    , "module-name" .= Aeson.toJSON (interfaceModName iface)
    , "library-name" .= Aeson.toJSON (interfaceLibName iface)
    , "exported-types" .= Aeson.toJSON
      (map
        snd
        (filter ((== IR.TypeScope) . fst) (Set.toList (interfaceExports iface)))
      )
    , "exported-values" .= Aeson.toJSON
      (map
        snd
        (filter ((== IR.ValueScope) . fst) (Set.toList (interfaceExports iface))
        )
      )
    , "types" .= encodeEntriesWhere isDataEntry
    , "type-synonyms" .= encodeEntriesWhere isTypeSynEntry
    , "constructors" .= encodeEntriesWhere isConEntry
    , "functions" .= encodeEntriesWhere isFuncEntry
    ]
   where
    -- | Encodes the entries of the environment that match the given predicate.
    encodeEntriesWhere :: (EnvEntry -> Bool) -> Aeson.Value
    encodeEntriesWhere p =
      Aeson.toJSON
        $ mapMaybe encodeEntry
        $ Set.toList
        $ Set.filter p
        $ interfaceEntries iface

-- | Encodes an entry of the environment.
encodeEntry :: EnvEntry -> Maybe Aeson.Value
encodeEntry entry
  | isDataEntry entry = return $ Aeson.object
    ["haskell-name" .= haskellName, "coq-name" .= coqName, "arity" .= arity]
  | isTypeSynEntry entry = return $ Aeson.object
    [ "haskell-name" .= haskellName
    , "coq-name" .= coqName
    , "arity" .= arity
    , "haskell-type" .= typeSyn
    , "type-arguments" .= typeArgs
    ]
  | isConEntry entry = do
    haskellType <- maybeHaskellType
    return $ Aeson.object
      [ "haskell-type" .= haskellType
      , "haskell-name" .= haskellName
      , "coq-name" .= coqName
      , "coq-smart-name" .= coqSmartName
      , "arity" .= arity
      ]
  | isFuncEntry entry = do
    haskellType <- maybeHaskellType
    return $ Aeson.object
      [ "haskell-type" .= haskellType
      , "haskell-name" .= haskellName
      , "coq-name" .= coqName
      , "arity" .= arity
      , "partial" .= partial
      , "needs-free-args" .= freeArgsNeeded
      ]
  | otherwise = error "encodeEntry: Cannot serialize (type) variable entry."
 where
  haskellName :: Aeson.Value
  haskellName = Aeson.toJSON (entryName entry)

  coqName, coqSmartName :: Aeson.Value
  coqName      = Aeson.toJSON (entryIdent entry)
  coqSmartName = Aeson.toJSON (entrySmartIdent entry)

  arity :: Aeson.Value
  arity = Aeson.toJSON (entryArity entry)

  partial :: Aeson.Value
  partial = Aeson.toJSON (entryIsPartial entry)

  freeArgsNeeded :: Aeson.Value
  freeArgsNeeded = Aeson.toJSON (entryNeedsFreeArgs entry)

  maybeHaskellType :: Maybe Aeson.Value
  maybeHaskellType = do
    returnType <- entryReturnType entry
    argTypes   <- sequence (entryArgTypes entry)
    let funcType = foldr (IR.FuncType NoSrcSpan) returnType argTypes
    return (Aeson.toJSON funcType)

  typeSyn :: Aeson.Value
  typeSyn = Aeson.toJSON (entryTypeSyn entry)

  typeArgs :: Aeson.Value
  typeArgs = Aeson.toJSON (entryTypeArgs entry)

-- | Serializes a module interface and writes it to a @.json@ file.
writeModuleInterface
  :: (MonadIO r, MonadReporter r) => FilePath -> ModuleInterface -> r ()
writeModuleInterface = saveConfig
