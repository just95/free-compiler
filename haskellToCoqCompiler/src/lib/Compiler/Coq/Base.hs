-- | This module contains the Coq identifiers of types, constructors and
--   functions defined in the Base library that accompanies the compiler.

module Compiler.Coq.Base where

import qualified Compiler.Coq.AST              as G

-------------------------------------------------------------------------------
-- Base library import                                                       --
-------------------------------------------------------------------------------

-- | Import sentence for the @Free@ and @Prelude@ modules from the Base
--   Coq library.
imports :: G.Sentence
imports =
  G.requireImportFrom (G.ident "Base") [G.ident "Free", G.ident "Prelude"]

-------------------------------------------------------------------------------
-- Free monad                                                                --
-------------------------------------------------------------------------------

-- | The Coq identifier for the @Free@ monad.
free :: G.Qualid
free = G.bare "Free"

-- | The Coq identifier for the @pure@ constructor of the @Free@ monad.
freePureCon :: G.Qualid
freePureCon = G.bare "pure"

-- | The Coq identifier for the @impure@ constructor of the @Free@ monad.
freeImpureCon :: G.Qualid
freeImpureCon = G.bare "impure"

-- | The Coq identifier for the @>>=@ operator of the @Free@ monad.
--
--   TODO does the pretty printer handle this right (e.g. w.r.t. precedence)?
freeBind :: G.Qualid
freeBind = G.bare "op_>>=__"

-- | The names and types of the parameters that must be passed to the @Free@
--   monad. These parameters are added automatically to every defined type and
--   function.
freeArgs :: [(G.Qualid, G.Term)]
freeArgs =
  [ (G.bare "Shape", G.Sort G.Type)
  , (G.bare "Pos", G.Arrow (G.Qualid (G.bare "Shape")) (G.Sort G.Type))
  ]

-------------------------------------------------------------------------------
-- Partiality                                                                --
-------------------------------------------------------------------------------

-- | The name and type of the @Partial@ instance that must be passed to
--   partial functions.
partialArg :: (G.Qualid, G.Term)
partialArg =
  ( G.bare "P"
  , G.app (G.Qualid (G.bare "Partial"))
          [G.Qualid (G.bare "Shape"), G.Qualid (G.bare "Pos")]
  )

-- | The identifier for the error term @undefined@.
partialUndefined :: G.Qualid
partialUndefined = G.bare "undefined"

-- | The identifier for the error term @error@.
partialError :: G.Qualid
partialError = G.bare "error"

-------------------------------------------------------------------------------
-- Reserved identifiers                                                      --
-------------------------------------------------------------------------------

-- | All Coq identifiers that are reserved for the Base library.
--
--   This does only include identifiers without corresponding Haskell name.
reservedIdents :: [G.Qualid]
reservedIdents =
  [ -- Free monad
    free
    , freePureCon
    , freeImpureCon
    -- Partiality
    , partialUndefined
    , partialError
    ]
    ++ map fst (partialArg : freeArgs)