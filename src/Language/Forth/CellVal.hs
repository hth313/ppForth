{-|

  Cell values.

-}

module Language.Forth.CellVal (CellVal(..),
                               true, false,
                               isValue, isAddress, isAny, isExecutionToken) where

import Data.Bits
import Data.Ord
import Data.Map (Map)
import Data.Word
import Language.Forth.Cell
import qualified Data.Vector as V
import Data.Vector.Storable.ByteString (ByteString)
import Language.Forth.Address
import {-# SOURCE #-} Language.Forth.Word

-- | Cell values are what we can put into a cell.This is also what goes
--   into a colon definition.
data CellVal cell = Address (Maybe Addr) |
                    Val cell |
                    XT (ForthWord cell) |
                    Loc (Maybe (IP cell)) |
                    Text ByteString |
                    Bot String
                    deriving (Eq, Show)

instance Cell cell => Ord (CellVal cell) where
    compare (Val a) (Val b) = compare a b
    compare (Address a) (Address b) = compare a b
    compare (XT a) (XT b) = comparing name a b


-- | Make 'CellVal cell' part of Num class. This allows us to use functions such as (+)
--   and many others direct on literals.
instance Cell cell => Num (CellVal cell) where
    (Val a) + (Val b) = Val (a + b)
    (Address (Just (Addr w off))) + (Val b) = Address (Just (Addr w (off + (fromIntegral b))))
    (Val b) + (Address (Just (Addr w off))) = Address (Just (Addr w (off +  (fromIntegral b))))
    a + b = Bot $ show a ++ " " ++ show b ++ " +"

    (Val a) - (Val b) = Val (a - b)
    (Address (Just (Addr w off))) - (Val b) =
         Address (Just (Addr w  (off + (negate $ fromIntegral b))))
    (Address (Just (Addr w1 off1))) - (Address (Just (Addr w2 off2)))
        | w1 == w2 = Val $ fromIntegral $ off1 - off2
    a - b
        | a == b = Val 0
        | otherwise = Bot $ show a ++ " " ++ show b ++ " -"

    (Val a) * (Val b) = Val (a * b)
    a * b = Bot $ show a ++ " " ++ show b ++ " *"

    abs (Val a) = Val (abs a)
    abs a = Bot $ show a ++ " ABS"

    negate (Val a) = Val (negate a)
    negate a = Bot $ show a ++ " NEGATE"

    signum (Val a) = Val (signum a)
    signum a = Bot $ show a ++ " SIGNUM"

    fromInteger n = Val (fromInteger n)


-- | Also make 'CellVal cell' part of Bits to allow further operations.
instance Cell cell => Bits (CellVal cell) where
    (Val a) .&. (Val b) = Val (a .&. b)
    a .&. b = Bot $ show a ++ " " ++ show b ++ " AND"
    (Val a) .|. (Val b) = Val (a .|. b)
    a .|. b = Bot $ show a ++ " " ++ show b ++ " OR"
    xor (Val a) (Val b) = Val (xor a b)
    xor a b = Bot $ show a ++ " " ++ show b ++ " XOR"
    complement (Val a) = Val (complement a)
    complement a = Bot $ show a ++ " INVERT"
    bitSize (Val a) = bitSize a
    isSigned (Val a) = isSigned a
    isSigned _ = False

-- | Boolean truth values.
true, false :: Cell cell => CellVal cell
true = Val (-1)
false = Val 0

isValue (Val _) = True
isValue _ = False
isAddress Address{} = True
isAddress _ = False
isAny = const True
isExecutionToken XT{} = True
isExecutionToken _ = False
