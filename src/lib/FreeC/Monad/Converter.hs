{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | This module defines a state monad which allows the compiler's state (see
--   "FreeC.Environment") to be passed implicitly through the converter.
--
--   There are also utility functions to modify the state and retrieve
--   information stored in the state.

module FreeC.Monad.Converter
  ( -- * State monad
    Converter
  , runConverter
  , evalConverter
  , execConverter
    -- * State monad transformer
  , ConverterT
  , runConverterT
  , evalConverterT
  , execConverterT
  , lift
  , lift'
  , hoist
    -- * Using IO actions in converters
  , ConverterIO
    -- * Modifying environments
  , MonadConverter(..)
  , getEnv
  , inEnv
  , putEnv
  , modifyEnv
  , modifyEnv'
    -- * Encapsulating environments
  , localEnv
  , moduleEnv
  , shadowVarPats
  )
where

import           Prelude                 hiding ( fail )

import           Control.Monad                  ( forM_ )
import           Control.Monad.Fail             ( MonadFail(..) )
import           Control.Monad.Identity         ( Identity(..) )
import           Control.Monad.State            ( StateT(..)
                                                , MonadIO(..)
                                                , MonadState(..)
                                                , MonadTrans(..)
                                                , evalStateT
                                                , execStateT
                                                , get
                                                , gets
                                                , modify
                                                , put
                                                , state
                                                )
import           Data.Composition               ( (.:) )

import           FreeC.Environment
import           FreeC.Environment.Entry
import qualified FreeC.IR.Syntax               as IR
import           FreeC.Monad.Class.Hoistable
import           FreeC.Monad.Reporter

-------------------------------------------------------------------------------
-- State monad                                                               --
-------------------------------------------------------------------------------

-- | Type synonym for the state monad used by the converter.
--
--   All converter functions usually require the current 'Environment'
--   to perform the conversion. This monad allows these functions to
--   pass the environment around implicitly.
--
--   Additionally the converter can report error messages and warnings to the
--   user if there is a problem while converting.
type Converter = ConverterT Identity

-- | Runs the converter with the given initial environment and
--   returns the converter's result as well as the final environment.
runConverter :: Converter a -> Environment -> Reporter (a, Environment)
runConverter = runConverterT

-- | Runs the converter with the given initial environment and
--   returns the converter's result.
evalConverter :: Converter a -> Environment -> Reporter a
evalConverter = evalConverterT

-- | Runs the converter with the given initial environment and
--   returns the final environment.
execConverter :: Converter a -> Environment -> Reporter Environment
execConverter = execConverterT

-------------------------------------------------------------------------------
-- State monad transformer                                                   --
-------------------------------------------------------------------------------

-- | A state monad used by the converter parameterized by the inner monad @m@.
newtype ConverterT m a
  = ConverterT { unwrapConverterT :: StateT Environment (ReporterT m) a }
  deriving (Functor, Applicative, Monad, MonadState Environment)

-- | Runs the converter with the given initial environment and
--   returns the converter's result as well as the final environment.
runConverterT
  :: Monad m => ConverterT m a -> Environment -> ReporterT m (a, Environment)
runConverterT = runStateT . unwrapConverterT

-- | Runs the converter with the given initial environment and
--   returns the converter's result.
evalConverterT :: Monad m => ConverterT m a -> Environment -> ReporterT m a
evalConverterT = evalStateT . unwrapConverterT

-- | Runs the converter with the given initial environment and
--   returns the final environment.
execConverterT
  :: Monad m => ConverterT m a -> Environment -> ReporterT m Environment
execConverterT = execStateT . unwrapConverterT

-- @MonadTrans@ instance for 'ConverterT'
instance MonadTrans ConverterT where
  lift mx = ConverterT $ StateT $ lift . (mx >>=) . (return .: flip (,))

-- | Converts a reporter to a converter.
lift' :: Monad m => ReporterT m a -> ConverterT m a
lift' mx = ConverterT $ StateT $ (mx >>=) . (return .: flip (,))

-- | The converter monad can be lifted to any converter transformer.
instance Hoistable ConverterT where
  hoist = ConverterT . StateT . (hoist .) . runConverter

-------------------------------------------------------------------------------
-- Using IO actions in converters                                            --
-------------------------------------------------------------------------------

-- | A converter with an IO action as its inner monad.
type ConverterIO = ConverterT IO

-- | IO actions can be embedded into converters.
instance MonadIO m => MonadIO (ConverterT m) where
  liftIO = ConverterT . liftIO

-------------------------------------------------------------------------------
-- Modifying environments                                                    --
-------------------------------------------------------------------------------

-- | Type class for monad a converter can be lifted to. Inside such monads,
--   the functions for modifying the converters environment can be called
--   without lifting them explicitly.
class Monad m => MonadConverter m where
  liftConverter :: Converter a -> m a

-- | Converters can be lifted to arbitrary converter transformers.
instance Monad m => MonadConverter (ConverterT m) where
  liftConverter = hoist

-- | Gets the current environment.
getEnv :: MonadConverter m => m Environment
getEnv = liftConverter get

-- | Gets a specific component of the current environment using the given
--   function to extract the value from the environment.
inEnv :: MonadConverter m => (Environment -> a) -> m a
inEnv = liftConverter . gets

-- | Sets the current environment.
putEnv :: MonadConverter m => Environment -> m ()
putEnv = liftConverter . put

-- | Applies the given function to the environment.
modifyEnv :: MonadConverter m => (Environment -> Environment) -> m ()
modifyEnv = liftConverter . modify

-- | Gets a specific component and modifies the environment.
modifyEnv' :: MonadConverter m => (Environment -> (a, Environment)) -> m a
modifyEnv' = liftConverter . state

-------------------------------------------------------------------------------
-- Encapsulating environments                                                --
-------------------------------------------------------------------------------

-- | Runs the given converter and returns its result but discards all
--   modifications to the environment.
localEnv :: MonadConverter m => m a -> m a
localEnv converter = do
  env <- getEnv
  x   <- converter
  putEnv env
  return x

-- | Like 'localEnv' but modules that are added to the environment are still
--   available afterwards.
moduleEnv :: MonadConverter m => m a -> m a
moduleEnv converter = do
  env <- getEnv
  x   <- converter
  ms  <- inEnv envAvailableModules
  putEnv env { envAvailableModules = ms }
  return x

-- | Adds entries for variable patterns during the execution of the given
--   converter.
--
--   Unlike 'localEnv', all modifications to the environment are kept
--   (except for added entries), except for the definition of the variables.
shadowVarPats :: MonadConverter m => [IR.VarPat] -> m a -> m a
shadowVarPats varPats converter = do
  oldEntries <- inEnv envEntries
  forM_ varPats $ \varPat -> modifyEnv $ addEntry VarEntry
    { entrySrcSpan = IR.varPatSrcSpan varPat
    , entryIsPure  = False
    , entryIdent   = undefined
    , entryName    = IR.varPatQName varPat
    , entryType    = IR.varPatType varPat
    }
  x <- converter
  modifyEnv $ \env -> env { envEntries = oldEntries }
  return x

-------------------------------------------------------------------------------
-- Reporting in converter                                                    --
-------------------------------------------------------------------------------

-- | Promotes a reporter to a converter that produces the same result and
--   ignores the environment.
--
--   This type class instance allows 'report' and 'reportFatal' to be used
--   directly in @do@-blocks of the 'Converter' monad without explicitly
--   lifting reporters.
instance Monad m => MonadReporter (ConverterT m) where
  liftReporter = ConverterT . lift . hoist

-- | Use 'MonadReporter' to lift @fail@ of 'Reporter' to a 'ConverterT'.
instance Monad m => MonadFail (ConverterT m) where
  fail = liftReporter . fail
