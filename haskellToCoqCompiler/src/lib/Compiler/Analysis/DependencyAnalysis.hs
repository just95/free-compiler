-- | This module contains functions to identify strongly connected components
--   of the dependency graph.
--
--   The dependency analysis is necessary because Coq does not allow functions
--   and data types to be used before they have been declared and we need to
--   identify (mutually) recursive functions.
--
--   The dependency analysis does not test whether there are undefined
--   identifiers. This is done by the converter.

module Compiler.Analysis.DependencyAnalysis
  ( DependencyComponent(..)
  , groupDependencies
  , groupTypeDecls
  , groupFuncDecls
  )
where

import           Data.Graph

import           Compiler.Analysis.DependencyGraph
import qualified Compiler.Haskell.AST          as HS

-- | A strongly connected component of the dependency graph.
--
--   All declarations that mutually depend on each other are in the same
--   strongly connected component.
--
--   The only difference to @'SCC' 'HS.Decl'@ is that the constructors
--   have been renamed to be more explainatory in the context of dependency
--   analysis.
data DependencyComponent =
  NonRecursive (HS.Decl) -- ^ A single non-recursive declaration.
  | Recursive [HS.Decl]  -- ^ A list of mutually recursive declarations.

-- | Converts a strongly connected component from @Data.Graph@ to a
--   'DependencyComponent'.
convertSCC :: SCC HS.Decl -> DependencyComponent
convertSCC (AcyclicSCC decl ) = NonRecursive decl
convertSCC (CyclicSCC  decls) = Recursive decls

-- | Computes the strongly connected components of the given dependency graph.
--
--   Each strongly connected component corresponds either to a set of mutually
--   recursive declarations or a single non-recursive declaration.
--
--   The returned list of strongly connected components is in reverse
--   topological order, i.e. a component @A@ precedes another component @B@ if
--   @A@ contains any declaration that depends on a declartion in $B$.
--   If two components do not depend on each other, they are in reverse
--   alphabetical order.
groupDependencies :: DependencyGraph -> [DependencyComponent]
groupDependencies = map convertSCC . stronglyConnComp . entries

-- | Combines the construction of the dependency graphs for the given
--   type declarations (See 'typeDependencyGraph') with the computaton of
--   strongly connected components.
groupTypeDecls :: [HS.Decl] -> [DependencyComponent]
groupTypeDecls decls = groupDependencies (typeDependencyGraph decls)

-- | Combines the construction of the dependency graphs for the given
--   function declarations (See 'funcDependencyGraph') with the computaton
--   of strongly connected components.
groupFuncDecls :: [HS.Decl] -> [DependencyComponent]
groupFuncDecls decls = groupDependencies (funcDependencyGraph decls)
