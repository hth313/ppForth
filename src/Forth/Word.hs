{-
  This file is part of Planet Pluto Forth.
  Copyright Håkan Thörngren 2013

  Forth word definition.

-}

module Forth.Word (ForthWord(..), IP(..), Body(..), LinkField) where

import Data.Char
import Data.Vector.Storable.ByteString.Char8 (ByteString)
import qualified Data.Vector.Storable.ByteString.Char8 as B
import Data.Vector (Vector)
import qualified Data.Vector as V
import Forth.WordId
import Forth.Types
import {-# SOURCE #-} Forth.Machine


-- | A Forth word
data ForthWord cell = ForthWord {
      name :: ByteString,
      immediate :: Bool,
      link :: LinkField cell,
      wid :: WordId,
      doer :: ForthWord cell -> ForthLambda cell,
      body :: Body cell
    }

instance Eq (ForthWord cell) where
    a == b = wid a == wid b

instance Show (ForthWord cell) where
    show = B.unpack . name

data Body cell = Native | Colon (ColonBody cell)
type LinkField cell = Maybe (ForthWord cell)
type ColonBody cell = Vector (Lit cell)

-- | Interpretive pointer
data IP cell = IP (ColonBody cell) Int deriving (Eq, Show)
