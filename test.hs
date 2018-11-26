module Test where
{-
Testfälle für bisherige Funktion des Compilers
-}


plus :: Int -> Int -> Int
plus a b = a + b


not :: Bool -> Bool
not b = case b of
  False -> True
  True -> False


{-append :: [a] -> [a] -> [a]
append xs ys = case xs of
  [] -> ys
  z:zs -> z : append zs ys-}

data Bool = True
        | False

data Maybe a = Nothing
              | Just a

data Either a b =
  Left a
  | Right b

data List a = Nil
            | Cons a (List a)

data Tree a =
  Leaf
  | Branch a (Tree a) (Tree a)
