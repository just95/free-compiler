# Changelog

## Unreleased

 - **Implemented module imports**
    + Imports of the form `import M` are now supported.
    + Module interface files are automatically created for converted modules.
 - **Implemented type inference**
    + Function type signatures are no longer required if the type of the function can be inferred.
    + Type arguments are passed explicitly in the generated Coq code.
 - **Added experimental support for pattern matching compilation**
    + Can be enabled using the `--transform-pattern-matching` command line option.
    + See [`doc/ExperimentalFeatures/PatternMatchingCompilation.hs`][] for details and current limitations.
 - **Added decreasing argument pragma**
    + Can be used to bypass our termination checker.
    + See [`doc/CustomPragmas/DecreasingArgumentPragma.md`][] for details
 - **Skip some unsupported Haskell features**
    + When the following unsupported Haskell language constructs are encountered, a warning rather than a fatal error is reported.
      * Unrecognized or unsupported pragmas
      * Import specifications (e.g. `import M hiding (...)`)
      * Type class contexts
      * Deriving clauses

## 0.1.0.0 / 2019-09-26

 - **Initial version**

[`doc/ExperimentalFeatures/PatternMatchingCompilation.hs`]: https://github.com/FreeProving/free-compiler/blob/master/doc/ExperimentalFeatures/PatternMatchingCompilation.hs

[`doc/CustomPragmas/DecreasingArgumentPragma.md`]: https://github.com/FreeProving/free-compiler/blob/master/doc/CustomPragmas/DecreasingArgumentPragma.md
