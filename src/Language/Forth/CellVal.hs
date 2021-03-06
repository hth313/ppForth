{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE CPP #-}
{-|

  Cell values.

-}

module Language.Forth.CellVal (Cell, CellVal(..), TargetToken(..),
                               trueVal, falseVal, isValue, isAddress, isAny,
                               bitSizeMaybe, isExecutionToken, isZero, cellToExpr) where

import Data.Bits
import Data.Int
import Data.Ord
import Data.Map (Map)
import Data.Word
import Language.Forth.Word
import Data.Vector.Storable.ByteString (ByteString)
import Language.Forth.Interpreter.Address
import Translator.Expression (Expr(Value, Identifier))
import Translator.Symbol

type Cell = Int32

data TargetToken = TargetToken WordId Symbol

-- | Cell values are what we can put into a data cell.
--   We parameterize over some integer type size (cell).
data CellVal a =
    Address (Maybe Addr)    -- ^ An address value
  | Val Cell                -- ^ A numeric value
  | XT (Maybe WordId) (Maybe String) (Maybe a) (Maybe TargetToken)
                            -- ^ Execution token
  | IP [a]                  -- ^ Pushed interpretive pointer
  | Text ByteString         -- ^ Some text buffer
  | HereColon WordId Int    -- ^ Pointer inside word being defined
  | Bot String

instance Eq (CellVal a) where
  Address a1 == Address a2 = a1 == a2
  Val n1     == Val n2     = n1 == n2
  Text t1    == Text t2    = t1 == t2
  _ == _ = False

instance Ord (CellVal a) where
  Address (Just (Addr wid1 off1)) <= Address (Just (Addr wid2 off2))
    | wid1 == wid2 = off1 <= off2
  Val n1 <= Val n2  = n1 <= n2
  _ <= _ = False

instance Show (CellVal a) where
  show (Address (Just adr))   = show adr
  show (Address Nothing)      = "null address"
  show (Val n)                = show n
  show (XT _ (Just name) _ _) = "xt(" ++ name ++ ")"
  show (XT _ Nothing _ _)     = "xt()"
  show IP{}                   = "ip-valuep"
  show (Text text)            = show text
  show (HereColon wid n)      = "HERE-address: " ++ show n
  show (Bot name)             = name

illegalValue = Bot "illegal value"

-- | Make 'CellVal cell' part of Num class. This allows us to use functions such as (+)
--   and many others direct on literals.
instance Num (CellVal a) where
    (Val a) + (Val b) = Val (a + b)
    (Address (Just (Addr w off))) + (Val b) = Address (Just (Addr w (off + (fromIntegral b))))
    (Val b) + (Address (Just (Addr w off))) = Address (Just (Addr w (off +  (fromIntegral b))))
    _ + _ = illegalValue

    (Val a) - (Val b) = Val (a - b)
    (Address (Just (Addr w off))) - (Val b) =
         Address (Just (Addr w  (off + (negate $ fromIntegral b))))
    (Address (Just (Addr w1 off1))) - (Address (Just (Addr w2 off2)))
        | w1 == w2 = Val $ fromIntegral $ off1 - off2
    a - b
        | a == b = Val 0
        | otherwise = illegalValue

    (Val a) * (Val b) = Val (a * b)
    _ * _ = illegalValue

    abs (Val a) = Val (abs a)
    abs _ = illegalValue

    negate (Val a) = Val (negate a)
    negate _ = illegalValue

    signum (Val a) = Val (signum a)
    signum _ = illegalValue

    fromInteger n = Val (fromInteger n)


-- | Also make 'CellVal cell' part of Bits to allow further operations.
instance Bits (CellVal a) where
    (Val a) .&. (Val b) = Val (a .&. b)
    a .&. b = illegalValue
    (Val a) .|. (Val b) = Val (a .|. b)
    a .|. b = illegalValue
    xor (Val a) (Val b) = Val (xor a b)
    xor a b = illegalValue
    complement (Val a) = Val (complement a)
    complement a = illegalValue
    bitSize (Val a) = bitSize a
    isSigned (Val a) = isSigned a
    isSigned _ = False
    shiftL (Val a) n = Val $ shiftL a n
    shiftR (Val a) n = Val $ shiftR a n
#if __GLASGOW_HASKELL__ >= 708
    bitSizeMaybe (Val a) = bitSizeMaybe a
#endif
    testBit (Val a) i = testBit a i
    popCount (Val a) = popCount a
    -- The following are not really implemented, just added to prevent
    -- GHC from warning
    rotate _ _ = illegalValue
    bit a = illegalValue

#if __GLASGOW_HASKELL__ < 708
bitSizeMaybe :: CellVal a -> Maybe Int
bitSizeMaybe = Just . bitSize
#endif

-- | Boolean truth values.
trueVal, falseVal :: CellVal a
trueVal = Val (-1)
falseVal = Val 0

isValue (Val _) = True
isValue _ = False
isAddress Address{} = True
isAddress _ = False
isAny = const True
isExecutionToken XT{} = True
isExecutionToken _ = False

isZero (Val 0) = True
isZero (Address Nothing) = True
isZero _ = False

cellToExpr (Val n) = Value $ fromIntegral n
cellToExpr (XT _ _ _ (Just (TargetToken _ sym))) = Identifier sym
