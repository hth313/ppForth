{-# LANGUAGE OverloadedStrings, RankNTypes, FlexibleContexts, TemplateHaskell #-}
{- |

   Build the dictionary.

-}

module Language.Forth.Dictionary (newDictionary, IDict(..), TDict(..), Dictionary(..),
                                  idict, idefining, compileList,
                                  latest, wids, tdict, tdefining, tcompileList,
                                  DefiningWrapper(..), TDefining(..),
                                  IDefining(..),
                                  definingWord, patchList,
                                  stateWId, toInWId,
                                  inputBufferWId, inputLineWId, tregWid,
                                  inputLineLengthWId, wordBufferWId, sourceIDWid,
                                  addWord, makeImmediate, setLatestImmediate) where

import Control.Lens hiding (over)
import Control.Monad
import Control.Monad.Trans.Class
import Control.Monad.Trans.State hiding (state)
import Data.Vector.Storable.ByteString.Char8 (ByteString)
import Data.Vector (Vector)
import Language.Forth.Interpreter.Address
import Language.Forth.Interpreter.CellMemory
import Language.Forth.Interpreter.DataField
import Language.Forth.CellVal
import Language.Forth.Primitive
import Language.Forth.Target
import Language.Forth.Word
import Translator.Assembler.Generate (IM)
import Prelude hiding (drop, or, and)

data IDict a = IDict {
    _idict  :: Dictionary a,
    _idefining :: Maybe (IDefining a)
}

-- | The defining state for the interpreter.
--   We collect words into a Vector together with information about locations
--   to change when we have collected all.
data IDefining a = IDefining {
    _compileList :: Vector (DefiningWrapper a)
  , _patchList :: [(Int, Int)]               -- ^ (loc, dest) list to patch
  , _defineFinalizer :: [a] -> a
  , _definingWord :: ForthWord a
}

-- | Wrapper for words being compile. This is used to keep track of branches
--   that are waiting to have their address fixed.
data DefiningWrapper a = WrapA a | WrapB ([a] -> a) | WrapRecurse

data TDict t = TDict {
    _tdict :: Dictionary (IM t)
  , _tdefining :: Maybe (TDefining t)
}

data TDefining t = TDefining  {
    _tcompileList :: IM t
}

data Dictionary a = Dictionary
  { _wids :: [WordId]
  , _latest :: LinkField a
  }

makeLenses ''IDict
makeLenses ''IDefining
makeLenses ''TDict
makeLenses ''TDefining
makeLenses ''Dictionary

-- Word identities are used to identify a particular word in a unique way.
-- They are used to find mutable datafields, which are stored separately in
-- the Forth state of the interpreter.
-- Some words (typically variables) that are needed early get their word
-- identity preallocated here and we use the tail for the rest of words.
(stateWId : toInWId : inputBufferWId : inputLineWId :
 inputLineLengthWId : wordBufferWId : sourceIDWid : tregWid : wordsIds) = map WordId [0..]

-- Create a new basic dictionary.
newDictionary :: Primitive a => State (Dictionary a) WordId -> Dictionary a
newDictionary extras = execState build (Dictionary wordsIds Nothing)
  where
    build = do
      addWord "EXIT"  exit
      addWord "EXECUTE" execute
      addWord "SWAP" swap
      addWord "DROP" drop
      addWord "OVER" over
      addWord "DUP"  dup
      addWord "R>"   rto
      addWord ">R"   tor
      addWord "R@"   rfetch
      addWord "+"    plus
      addWord "-"    minus
      addWord "AND"  and
      addWord "OR"   or
      addWord "XOR"  xor
      addWord "2*"   twoStar
      addWord "2/"   twoSlash
      addWord "LSHIFT" lshift
      addWord "RSHIFT" rshift
      addWord "0="   zerop
      addWord "0<"   lt0
      addWord "!"    store
      addWord "C!"   cstore
      addWord "@"    fetch
      addWord "C@"   cfetch
      addWord "CONSTANT" constant
      addWord "UM*" umstar
      addWord "UM/MOD" ummod
      extras

addWord name doer =
  StateT $ \s ->
    let i:is = _wids s
    in  return (i, s { _wids = is,
                       _latest = Just $ ForthWord name False (_latest s) i doer })

makeImmediate :: State (Dictionary a)  ()
makeImmediate = modify setLatestImmediate

setLatestImmediate = latest._Just.immediateFlag.~True
